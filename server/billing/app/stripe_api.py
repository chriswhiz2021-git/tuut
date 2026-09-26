"""Stripe über die REST-API (ohne SDK – stabil und versionsunabhängig).

Checkout-Sitzungen anlegen/abrufen und Webhook-Signaturen prüfen.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import time

import httpx

API = "https://api.stripe.com/v1"


class StripeError(Exception):
    pass


def configured() -> bool:
    return bool(os.environ.get("STRIPE_SECRET_KEY", "").strip())


def _key() -> str:
    k = os.environ.get("STRIPE_SECRET_KEY", "").strip()
    if not k:
        raise StripeError("Stripe ist noch nicht eingerichtet: STRIPE_SECRET_KEY fehlt in einstellungen.env.")
    return k


def _raise_for(r: httpx.Response) -> None:
    if r.status_code < 400:
        return
    try:
        msg = r.json()["error"]["message"]
    except Exception:
        msg = r.text[:300]
    raise StripeError(f"Stripe meldet: {msg}")


def create_checkout(amount_cents: int, user_id: str, success_url: str, cancel_url: str) -> dict:
    data = {
        "mode": "payment",
        "success_url": success_url,
        "cancel_url": cancel_url,
        "client_reference_id": user_id,
        "metadata[user_id]": user_id,
        "locale": "de",
        "line_items[0][quantity]": "1",
        "line_items[0][price_data][currency]": "eur",
        "line_items[0][price_data][unit_amount]": str(amount_cents),
        "line_items[0][price_data][product_data][name]": "Tuut-Guthaben",
    }
    try:
        r = httpx.post(f"{API}/checkout/sessions", data=data, auth=(_key(), ""), timeout=20)
    except httpx.HTTPError as e:
        raise StripeError(f"Stripe nicht erreichbar: {e}") from e
    _raise_for(r)
    return r.json()


def retrieve_checkout(session_id: str) -> dict:
    try:
        r = httpx.get(f"{API}/checkout/sessions/{session_id}", auth=(_key(), ""), timeout=20)
    except httpx.HTTPError as e:
        raise StripeError(f"Stripe nicht erreichbar: {e}") from e
    _raise_for(r)
    return r.json()


def verify_webhook(payload: bytes, sig_header: str | None, secret: str, tolerance: int = 300, now: float | None = None) -> dict:
    """Prüft die Stripe-Signatur (Header 'Stripe-Signature: t=…,v1=…') und liefert das Ereignis."""
    if not sig_header:
        raise StripeError("Signatur fehlt")
    ts = None
    sigs = []
    for part in sig_header.split(","):
        k, _, v = part.strip().partition("=")
        if k == "t":
            try:
                ts = int(v)
            except ValueError:
                raise StripeError("Zeitstempel ungültig")
        elif k == "v1":
            sigs.append(v)
    if ts is None or not sigs:
        raise StripeError("Signatur unvollständig")
    expected = hmac.new(secret.encode(), f"{ts}.".encode() + payload, hashlib.sha256).hexdigest()
    if not any(hmac.compare_digest(expected, s) for s in sigs):
        raise StripeError("Signatur stimmt nicht")
    if abs((now if now is not None else time.time()) - ts) > tolerance:
        raise StripeError("Signatur zu alt")
    return json.loads(payload)
