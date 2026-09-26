"""Tuut-Guthaben – Guthaben, Tarife und Abrechnung für Festnetzgespräche.

Grundsätze:
  * Alle Beträge in ganzen Cent (keine Fließkommazahlen).
  * Jede Bewegung steht im Journal (Tabelle ledger), doppelte Buchungen verhindert eine Datenbank-Regel.
  * Aufladungen werden erst nach bestätigter Zahlung bei Stripe gutgeschrieben – egal ob über
    Rücksprungseite, App-Aktualisierung oder Webhook, und immer nur einmal.
  * Vor jedem Gespräch wird Guthaben reserviert (Zeilensperre), damit parallele Gespräche
    dasselbe Guthaben nicht mehrfach verbrauchen. Abgerechnet wird nach vom Server gemessener Zeit.
"""
from __future__ import annotations

import html
import logging
import os
import threading
import time
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone

import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from starlette.concurrency import run_in_threadpool

from . import db, pricing, providers, stripe_api

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("tuut.billing")


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, "").strip() or default)
    except ValueError:
        return default


SYNAPSE_URL = os.environ.get("SYNAPSE_URL", "http://synapse:8008").rstrip("/")
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "http://localhost:8787").strip().rstrip("/")
STRIPE_WEBHOOK_SECRET = os.environ.get("STRIPE_WEBHOOK_SECRET", "").strip()
PROVIDER_WEBHOOK_SECRET = os.environ.get("ANBIETER_WEBHOOK_SECRET", "").strip()
MAX_RESERVIERUNG_CENT = _env_int("MAX_RESERVIERUNG_CENT", 1000)
TAGESLIMIT_CENT = _env_int("TAGESLIMIT_CENT", 2000)
MAX_PARALLELE_GESPRAECHE = _env_int("MAX_PARALLELE_GESPRAECHE", 1)
MAX_GESPRAECH_SEKUNDEN = _env_int("MAX_GESPRAECH_SEKUNDEN", 4 * 3600)
AUFLADEBETRAEGE_CENT = (500, 1000, 2000, 5000)
HEARTBEAT_TIMEOUT = 90       # Sekunden ohne Lebenszeichen -> Gespräch wird serverseitig beendet
RESERVIERUNG_TIMEOUT = 180   # Sekunden bis eine nie verbundene Reservierung freigegeben wird

TARIFE = pricing.TariffTable.load(os.environ.get("TARIF_DATEI", "/app/tarife.json"))


# --------------------------------------------------------------------------- Start

def _sweeper_loop() -> None:
    while True:
        try:
            sweep_stale_calls()
        except Exception:
            log.exception("Aufräumen hängender Gespräche fehlgeschlagen")
        time.sleep(30)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    db.init_schema()
    threading.Thread(target=_sweeper_loop, daemon=True).start()
    yield


app = FastAPI(title="Tuut-Guthaben", lifespan=lifespan)


# --------------------------------------------------------------------------- Anmeldung

_token_cache: dict[str, tuple[str, float]] = {}


def current_user(authorization: str | None) -> str:
    """Prüft das Matrix-Zugangstoken der App beim eigenen Matrix-Server."""
    if not authorization or not authorization.startswith("Bearer ") or len(authorization) < 12:
        raise HTTPException(401, "Nicht angemeldet.")
    token = authorization[7:]
    cached = _token_cache.get(token)
    if cached and cached[1] > time.time():
        return cached[0]
    try:
        r = httpx.get(f"{SYNAPSE_URL}/_matrix/client/v3/account/whoami",
                      headers={"Authorization": f"Bearer {token}"}, timeout=10)
    except httpx.HTTPError:
        raise HTTPException(503, "Matrix-Server nicht erreichbar.")
    if r.status_code != 200:
        raise HTTPException(401, "Anmeldung ungültig. Bitte in der App ab- und wieder anmelden.")
    user_id = r.json()["user_id"]
    if len(_token_cache) > 1000:
        _token_cache.clear()
    _token_cache[token] = (user_id, time.time() + 300)
    return user_id


# --------------------------------------------------------------------------- Hilfen

def _now() -> datetime:
    return datetime.now(timezone.utc)


def _tariff_of(row: dict) -> pricing.Tariff:
    return pricing.Tariff(row["number"], row["destination"], False, "", int(row["rate_hc"]),
                          int(row["fee_cents"]), int(row["takt_first"]), int(row["takt_next"]))


def _page(title: str, text: str) -> HTMLResponse:
    body = f"""<!doctype html><html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>{html.escape(title)}</title>
<style>body{{font-family:system-ui,sans-serif;max-width:520px;margin:12vh auto;padding:0 20px;text-align:center}}
h1{{color:#1F6F5F}}p{{font-size:1.15rem;line-height:1.5}}</style></head>
<body><h1>{html.escape(title)}</h1><p>{html.escape(text)}</p><p>Du kannst dieses Fenster schließen und zur Tuut-App zurückkehren.</p></body></html>"""
    return HTMLResponse(body)


def _account_view(conn, user_id: str) -> dict:
    row = conn.execute("SELECT balance_cents, reserved_cents, blocked FROM accounts WHERE user_id=%s",
                       (user_id,)).fetchone()
    bal, res = int(row["balance_cents"]), int(row["reserved_cents"])
    return {
        "guthaben_cent": bal,
        "reserviert_cent": res,
        "verfuegbar_cent": bal - res,
        "guthaben_text": pricing.euro(bal),
        "verfuegbar_text": pricing.euro(bal - res),
        "gesperrt": bool(row["blocked"]),
    }


# --------------------------------------------------------------------------- Aufladung (Stripe)

def credit_session(session: dict) -> str:
    """Schreibt eine bezahlte Stripe-Checkout-Sitzung genau einmal gut. Liefert den Status."""
    sid = session.get("id", "")
    with db.connect() as conn:
        top = conn.execute("SELECT * FROM topups WHERE session_id=%s FOR UPDATE", (sid,)).fetchone()
        if top is None:
            log.warning("Unbekannte Stripe-Sitzung %s – ignoriert", sid)
            return "unbekannt"
        if top["status"] == "paid":
            return "paid"
        if session.get("payment_status") != "paid":
            if session.get("status") == "expired":
                conn.execute("UPDATE topups SET status='expired' WHERE session_id=%s", (sid,))
                return "expired"
            return "open"
        ok = (
            str(session.get("currency", "")).lower() == "eur"
            and int(session.get("amount_total") or 0) == int(top["amount_cents"])
            and session.get("client_reference_id") == top["user_id"]
        )
        if not ok:
            log.error("Stripe-Sitzung %s passt nicht zur Aufladung – zur Prüfung markiert", sid)
            conn.execute("UPDATE topups SET status='pruefen' WHERE session_id=%s", (sid,))
            return "pruefen"
        user_id, amount = top["user_id"], int(top["amount_cents"])
        db.ensure_account(conn, user_id)
        acc = conn.execute("SELECT balance_cents FROM accounts WHERE user_id=%s FOR UPDATE", (user_id,)).fetchone()
        new_balance = int(acc["balance_cents"]) + amount
        inserted = conn.execute(
            """INSERT INTO ledger (user_id, kind, reference, amount_cents, balance_after_cents, text)
               VALUES (%s, 'topup', %s, %s, %s, %s) ON CONFLICT (kind, reference) DO NOTHING RETURNING id""",
            (user_id, sid, amount, new_balance, f"Aufladung {pricing.euro(amount)} (Stripe)"),
        ).fetchone()
        if inserted:
            conn.execute("UPDATE accounts SET balance_cents=%s WHERE user_id=%s", (new_balance, user_id))
        conn.execute("UPDATE topups SET status='paid', credited_at=now() WHERE session_id=%s", (sid,))
        log.info("Aufladung %s für %s gutgeschrieben (%s)", pricing.euro(amount), user_id, sid)
        return "paid"


def sync_open_topups(user_id: str) -> None:
    """Fragt offene Aufladungen des Nutzers bei Stripe ab – funktioniert auch ohne Webhook (lokal)."""
    if not stripe_api.configured():
        return
    with db.connect() as conn:
        rows = conn.execute(
            """SELECT session_id FROM topups WHERE user_id=%s AND status='open'
               AND created_at > now() - interval '2 days' ORDER BY created_at DESC LIMIT 5""",
            (user_id,),
        ).fetchall()
    for row in rows:
        try:
            credit_session(stripe_api.retrieve_checkout(row["session_id"]))
        except stripe_api.StripeError as e:
            log.warning("Abfrage %s fehlgeschlagen: %s", row["session_id"], e)


class TopupBody(BaseModel):
    betrag_cent: int


@app.post("/api/aufladen")
def topup_checkout(body: TopupBody, authorization: str | None = Header(default=None)):
    user_id = current_user(authorization)
    if body.betrag_cent not in AUFLADEBETRAEGE_CENT:
        raise HTTPException(400, "Ungültiger Betrag.")
    try:
        session = stripe_api.create_checkout(
            body.betrag_cent, user_id,
            success_url=f"{PUBLIC_BASE_URL}/aufladen/ok?session_id={{CHECKOUT_SESSION_ID}}",
            cancel_url=f"{PUBLIC_BASE_URL}/aufladen/abbruch",
        )
    except stripe_api.StripeError as e:
        raise HTTPException(409, str(e))
    with db.connect() as conn:
        db.ensure_account(conn, user_id)
        conn.execute("INSERT INTO topups (session_id, user_id, amount_cents) VALUES (%s, %s, %s)",
                     (session["id"], user_id, body.betrag_cent))
    return {"url": session["url"]}


@app.get("/aufladen/ok")
def topup_ok(session_id: str = ""):
    try:
        ergebnis = credit_session(stripe_api.retrieve_checkout(session_id)) if session_id else "unbekannt"
    except stripe_api.StripeError as e:
        return _page("Zahlung wird geprüft", f"Die Bestätigung konnte noch nicht abgerufen werden ({e}). "
                                             "Tippe in der App auf „Aktualisieren“.")
    if ergebnis == "paid":
        return _page("Danke!", "Die Zahlung ist bestätigt und dein Guthaben wurde gutgeschrieben.")
    if ergebnis == "open":
        return _page("Zahlung wird geprüft", "Stripe hat die Zahlung noch nicht bestätigt. "
                                             "Tippe gleich in der App auf „Aktualisieren“.")
    return _page("Zahlung nicht gutgeschrieben", "Diese Zahlung konnte nicht zugeordnet werden. Es wurde nichts gebucht.")


@app.get("/aufladen/abbruch")
def topup_cancel():
    return _page("Abgebrochen", "Die Aufladung wurde abgebrochen. Es wurde nichts abgebucht.")


@app.post("/api/stripe/webhook")
async def stripe_webhook(request: Request):
    if not STRIPE_WEBHOOK_SECRET:
        raise HTTPException(503, "Webhook nicht eingerichtet (STRIPE_WEBHOOK_SECRET fehlt).")
    payload = await request.body()
    try:
        event = stripe_api.verify_webhook(payload, request.headers.get("stripe-signature"), STRIPE_WEBHOOK_SECRET)
    except stripe_api.StripeError as e:
        raise HTTPException(400, f"Ungültige Signatur: {e}")
    if event.get("type") in ("checkout.session.completed", "checkout.session.async_payment_succeeded"):
        await run_in_threadpool(credit_session, event["data"]["object"])
    return {"ok": True}


# --------------------------------------------------------------------------- Status, Journal

@app.get("/health")
def health():
    return {"ok": True}


@app.get("/api/status")
def status(authorization: str | None = Header(default=None)):
    user_id = current_user(authorization)
    sync_open_topups(user_id)
    aktiv, info = providers.status()
    with db.connect() as conn:
        db.ensure_account(conn, user_id)
        view = _account_view(conn, user_id)
    view.update({
        "telefonie_aktiv": aktiv,
        "telefonie_hinweis": "" if aktiv else info,
        "stripe_aktiv": stripe_api.configured(),
        "aufladebetraege_cent": list(AUFLADEBETRAEGE_CENT),
    })
    return view


@app.get("/api/journal")
def journal(authorization: str | None = Header(default=None)):
    user_id = current_user(authorization)
    with db.connect() as conn:
        rows = conn.execute(
            """SELECT created_at, kind, amount_cents, balance_after_cents, text FROM ledger
               WHERE user_id=%s ORDER BY id DESC LIMIT 100""", (user_id,)).fetchall()
    return {"eintraege": [{
        "zeit": r["created_at"].isoformat(),
        "art": r["kind"],
        "betrag_cent": int(r["amount_cents"]),
        "betrag_text": pricing.euro(int(r["amount_cents"])),
        "saldo_text": pricing.euro(int(r["balance_after_cents"])),
        "text": r["text"],
    } for r in rows]}


# --------------------------------------------------------------------------- Tarifauskunft

@app.get("/api/tarif")
def tariff_info(nummer: str, authorization: str | None = Header(default=None)):
    user_id = current_user(authorization)
    try:
        digits = pricing.normalize_number(nummer)
    except pricing.NumberError as e:
        return {"erlaubt": False, "grund": str(e)}
    t = TARIFE.match(digits)
    if t is None:
        return {"erlaubt": False, "nummer": pricing.format_number(digits),
                "grund": "Für dieses Ziel ist noch kein Preis hinterlegt."}
    if t.blocked:
        return {"erlaubt": False, "nummer": pricing.format_number(digits), "ziel": t.name,
                "grund": f"Gesperrt: {t.reason}"}
    with db.connect() as conn:
        db.ensure_account(conn, user_id)
        view = _account_view(conn, user_id)
    budget = min(view["verfuegbar_cent"], MAX_RESERVIERUNG_CENT)
    return {
        "erlaubt": True,
        "nummer": pricing.format_number(digits),
        "ziel": t.name,
        "preis_text": t.rate_text,
        "takt_text": t.takt_text,
        "verbindungsgebuehr_text": pricing.euro(t.fee_cents) if t.fee_cents else "keine",
        "max_minuten": pricing.max_seconds(budget, t, MAX_GESPRAECH_SEKUNDEN) // 60 if budget > 0 else 0,
    }


# --------------------------------------------------------------------------- Gespräche

class StartBody(BaseModel):
    nummer: str


@app.post("/api/gespraech/start")
def call_start(body: StartBody, authorization: str | None = Header(default=None)):
    user_id = current_user(authorization)
    try:
        digits = pricing.normalize_number(body.nummer)
    except pricing.NumberError as e:
        raise HTTPException(400, str(e))
    t = TARIFE.match(digits)
    if t is None:
        raise HTTPException(403, "Für dieses Ziel ist noch kein Preis hinterlegt.")
    if t.blocked:
        raise HTTPException(403, f"Dieses Ziel ist gesperrt: {t.reason}")
    aktiv, info = providers.status()
    if not aktiv:
        raise HTTPException(409, info)

    call_id = str(uuid.uuid4())
    with db.connect() as conn:
        db.ensure_account(conn, user_id)
        acc = conn.execute("SELECT * FROM accounts WHERE user_id=%s FOR UPDATE", (user_id,)).fetchone()
        if acc["blocked"]:
            raise HTTPException(403, "Dein Konto ist für Festnetzgespräche gesperrt.")
        active = conn.execute("SELECT count(*) AS n FROM pstn_calls WHERE user_id=%s AND status IN ('reserved','connected')",
                              (user_id,)).fetchone()["n"]
        if active >= MAX_PARALLELE_GESPRAECHE:
            raise HTTPException(409, "Es läuft bereits ein Festnetzgespräch.")
        spent_today = conn.execute(
            """SELECT COALESCE(SUM(-amount_cents), 0) AS s FROM ledger
               WHERE user_id=%s AND kind='call' AND created_at >= date_trunc('day', now())""",
            (user_id,)).fetchone()["s"]
        available = int(acc["balance_cents"]) - int(acc["reserved_cents"])
        day_left = TAGESLIMIT_CENT - int(spent_today) - int(acc["reserved_cents"])
        budget = min(available, MAX_RESERVIERUNG_CENT, day_left)
        seconds = pricing.max_seconds(budget, t, MAX_GESPRAECH_SEKUNDEN) if budget > 0 else 0
        if seconds == 0:
            if day_left < pricing.cost_cents(1, t):
                raise HTTPException(402, f"Tageslimit von {pricing.euro(TAGESLIMIT_CENT)} erreicht.")
            raise HTTPException(402, "Dein Guthaben reicht für dieses Gespräch nicht. Bitte aufladen.")
        reserve = pricing.cost_cents(seconds, t)
        conn.execute("UPDATE accounts SET reserved_cents = reserved_cents + %s WHERE user_id=%s", (reserve, user_id))
        conn.execute(
            """INSERT INTO pstn_calls (id, user_id, number, destination, rate_hc, fee_cents, takt_first, takt_next,
                                       reserved_cents, max_seconds, status, provider)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'reserved',%s)""",
            (call_id, user_id, digits, t.name, t.rate_hc, t.fee_cents, t.first, t.next, reserve, seconds, info),
        )
    return {"gespraech_id": call_id, "max_sekunden": seconds, "reserviert_text": pricing.euro(reserve)}


def _own_call(conn, call_id: str, user_id: str, lock: bool = False) -> dict:
    row = conn.execute("SELECT * FROM pstn_calls WHERE id=%s" + (" FOR UPDATE" if lock else ""), (call_id,)).fetchone()
    if row is None or row["user_id"] != user_id:
        raise HTTPException(404, "Gespräch nicht gefunden.")
    return row


@app.post("/api/gespraech/{call_id}/verbunden")
def call_connected(call_id: str, authorization: str | None = Header(default=None)):
    user_id = current_user(authorization)
    with db.connect() as conn:
        row = _own_call(conn, call_id, user_id, lock=True)
        if row["status"] == "reserved":
            conn.execute("UPDATE pstn_calls SET status='connected', connected_at=now(), last_heartbeat_at=now() WHERE id=%s",
                         (call_id,))
    return {"ok": True}


@app.post("/api/gespraech/{call_id}/lebenszeichen")
def call_heartbeat(call_id: str, authorization: str | None = Header(default=None)):
    user_id = current_user(authorization)
    with db.connect() as conn:
        row = _own_call(conn, call_id, user_id, lock=True)
        if row["status"] != "connected":
            return {"sekunden": 0, "kosten_text": pricing.euro(0), "auflegen": row["status"] == "ended"}
        conn.execute("UPDATE pstn_calls SET last_heartbeat_at=now() WHERE id=%s", (call_id,))
        seconds = int((_now() - row["connected_at"]).total_seconds())
    t = _tariff_of(row)
    return {
        "sekunden": seconds,
        "kosten_text": pricing.euro(pricing.cost_cents(min(seconds, row["max_seconds"]), t)),
        "rest_sekunden": max(0, row["max_seconds"] - seconds),
        "auflegen": seconds >= row["max_seconds"],
    }


def finalize_call(call_id: str, end_time: datetime | None = None) -> dict:
    """Beendet ein Gespräch genau einmal: Kosten buchen, Reservierung freigeben."""
    with db.connect() as conn:
        head = conn.execute("SELECT user_id FROM pstn_calls WHERE id=%s", (call_id,)).fetchone()
        if head is None:
            raise HTTPException(404, "Gespräch nicht gefunden.")
        user_id = head["user_id"]
        # Sperrreihenfolge immer: Konto, dann Gespräch.
        acc = conn.execute("SELECT balance_cents FROM accounts WHERE user_id=%s FOR UPDATE", (user_id,)).fetchone()
        row = conn.execute("SELECT * FROM pstn_calls WHERE id=%s FOR UPDATE", (call_id,)).fetchone()
        if row["status"] == "ended":
            return {"kosten_text": pricing.euro(int(row["cost_cents"] or 0)), "sekunden": int(row["billed_seconds"] or 0)}
        end = end_time or _now()
        if row["connected_at"] is not None:
            duration = max(0, min(int((end - row["connected_at"]).total_seconds()), int(row["max_seconds"])))
        else:
            duration = 0
        t = _tariff_of(row)
        cost = min(pricing.cost_cents(duration, t), int(row["reserved_cents"]))
        billed = pricing.billed_seconds(duration, t.first, t.next)
        new_balance = int(acc["balance_cents"]) - cost
        if cost > 0:
            conn.execute(
                """INSERT INTO ledger (user_id, kind, reference, amount_cents, balance_after_cents, text)
                   VALUES (%s, 'call', %s, %s, %s, %s) ON CONFLICT (kind, reference) DO NOTHING""",
                (user_id, call_id, -cost, new_balance,
                 f"Gespräch {pricing.format_number(row['number'])} ({row['destination']}), {duration} s"),
            )
        conn.execute("UPDATE accounts SET balance_cents = balance_cents - %s, reserved_cents = reserved_cents - %s WHERE user_id=%s",
                     (cost, int(row["reserved_cents"]), user_id))
        conn.execute("UPDATE pstn_calls SET status='ended', ended_at=%s, billed_seconds=%s, cost_cents=%s WHERE id=%s",
                     (end, billed, cost, call_id))
        return {"kosten_text": pricing.euro(cost), "sekunden": duration}


@app.post("/api/gespraech/{call_id}/ende")
def call_end(call_id: str, authorization: str | None = Header(default=None)):
    user_id = current_user(authorization)
    with db.connect() as conn:
        _own_call(conn, call_id, user_id)
    return finalize_call(call_id)


def sweep_stale_calls() -> None:
    now = _now()
    with db.connect() as conn:
        rows = conn.execute(
            """SELECT id, status, last_heartbeat_at FROM pstn_calls
               WHERE (status='connected' AND last_heartbeat_at < %s)
                  OR (status='reserved' AND created_at < %s)""",
            (now - timedelta(seconds=HEARTBEAT_TIMEOUT), now - timedelta(seconds=RESERVIERUNG_TIMEOUT))).fetchall()
    for r in rows:
        end = r["last_heartbeat_at"] if r["status"] == "connected" else None
        finalize_call(r["id"], end_time=end or _now())
        log.info("Gespräch %s serverseitig beendet (%s)", r["id"], r["status"])


@app.get("/api/gespraeche")
def call_list(authorization: str | None = Header(default=None)):
    user_id = current_user(authorization)
    with db.connect() as conn:
        rows = conn.execute(
            """SELECT created_at, number, destination, status, billed_seconds, cost_cents FROM pstn_calls
               WHERE user_id=%s ORDER BY created_at DESC LIMIT 100""", (user_id,)).fetchall()
    return {"gespraeche": [{
        "zeit": r["created_at"].isoformat(),
        "nummer": pricing.format_number(r["number"]),
        "ziel": r["destination"],
        "status": r["status"],
        "sekunden": int(r["billed_seconds"] or 0),
        "kosten_text": pricing.euro(int(r["cost_cents"] or 0)),
    } for r in rows]}


# --------------------------------------------------------------------------- Abgleich mit dem Anbieter

class CdrBody(BaseModel):
    anbieter: str
    anbieter_gespraech_id: str
    gespraech_id: str | None = None
    sekunden: int


@app.post("/api/anbieter/abrechnung")
def provider_cdr(body: CdrBody, x_tuut_secret: str | None = Header(default=None)):
    """Abrechnungsdaten des Anbieters entgegennehmen und mit der eigenen Abrechnung vergleichen."""
    if not PROVIDER_WEBHOOK_SECRET or x_tuut_secret != PROVIDER_WEBHOOK_SECRET:
        raise HTTPException(401, "Nicht berechtigt.")
    abweichung = None
    with db.connect() as conn:
        if body.gespraech_id:
            row = conn.execute("SELECT billed_seconds, status FROM pstn_calls WHERE id=%s", (body.gespraech_id,)).fetchone()
            if row is None:
                abweichung = "Gespräch bei uns unbekannt"
            elif row["status"] != "ended":
                abweichung = "Gespräch bei uns noch nicht beendet"
            elif int(row["billed_seconds"] or 0) < body.sekunden:
                abweichung = f"Anbieter {body.sekunden} s, wir {row['billed_seconds']} s abgerechnet"
        conn.execute(
            """INSERT INTO provider_cdrs (provider, provider_call_id, call_id, seconds, abweichung)
               VALUES (%s,%s,%s,%s,%s) ON CONFLICT (provider, provider_call_id) DO NOTHING""",
            (body.anbieter, body.anbieter_gespraech_id, body.gespraech_id, body.sekunden, abweichung),
        )
    if abweichung:
        log.error("Abrechnungsabweichung %s: %s", body.anbieter_gespraech_id, abweichung)
    return {"ok": True, "abweichung": abweichung}
