"""Tarife, Rufnummern und Kostenberechnung – ohne Fließkommazahlen.

Einheiten:
  * Guthaben und Kosten: ganze Cent
  * Minutenpreise: Hundertstel-Cent (hc) pro Minute, z. B. 5,00 ct/Min = 500 hc
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation

NOTRUF = {"110", "112", "116116", "116117"}


class NumberError(ValueError):
    """Rufnummer ungültig oder nicht wählbar (Meldung ist für den Nutzer gedacht)."""


@dataclass(frozen=True)
class Tariff:
    prefix: str          # E.164 ohne "+", z. B. "49"
    name: str
    blocked: bool
    reason: str
    rate_hc: int         # Hundertstel-Cent pro Minute
    fee_cents: int       # Verbindungsgebühr je Gespräch (nur bei Verbindung)
    first: int           # erster Takt in Sekunden
    next: int            # Folgetakt in Sekunden

    @property
    def rate_text(self) -> str:
        return f"{self.rate_hc // 100},{self.rate_hc % 100:02d} ct/Min"

    @property
    def takt_text(self) -> str:
        return f"{self.first}/{self.next}"


def parse_rate_hc(text: str) -> int:
    try:
        value = Decimal(str(text).replace(",", ".")) * 100
    except InvalidOperation as e:
        raise ValueError(f"Ungültiger Preis: {text!r}") from e
    if value < 0 or value != value.to_integral_value():
        raise ValueError(f"Preis {text!r} hat mehr als zwei Nachkommastellen oder ist negativ")
    return int(value)


def parse_takt(text: str) -> tuple[int, int]:
    m = re.fullmatch(r"\s*(\d+)\s*/\s*(\d+)\s*", str(text))
    if not m or int(m.group(1)) < 1 or int(m.group(2)) < 1:
        raise ValueError(f"Ungültiger Takt: {text!r} (erwartet z. B. 60/60)")
    return int(m.group(1)), int(m.group(2))


class TariffTable:
    def __init__(self, tariffs: list[Tariff]):
        self.tariffs = sorted(tariffs, key=lambda t: len(t.prefix), reverse=True)

    @classmethod
    def from_json(cls, data: dict) -> "TariffTable":
        out = []
        for row in data.get("tarife", []):
            prefix = str(row["praefix"]).lstrip("+")
            if not prefix.isdigit():
                raise ValueError(f"Ungültiges Präfix: {row['praefix']!r}")
            blocked = bool(row.get("gesperrt", False))
            if blocked:
                out.append(Tariff(prefix, row.get("name", prefix), True, row.get("grund", "Ziel gesperrt"), 0, 0, 60, 60))
                continue
            first, nxt = parse_takt(row.get("takt", "60/60"))
            out.append(Tariff(
                prefix=prefix,
                name=row.get("name", prefix),
                blocked=False,
                reason="",
                rate_hc=parse_rate_hc(row["cent_pro_minute"]),
                fee_cents=int(row.get("verbindungsgebuehr_cent", 0)),
                first=first,
                next=nxt,
            ))
        return cls(out)

    @classmethod
    def load(cls, path: str) -> "TariffTable":
        with open(path, encoding="utf-8") as f:
            return cls.from_json(json.load(f))

    def match(self, digits: str) -> Tariff | None:
        for t in self.tariffs:
            if digits.startswith(t.prefix):
                return t
        return None


def normalize_number(raw: str, default_cc: str = "49") -> str:
    """Wandelt Eingaben wie '030 123456', '+49 30 123456', '0049…' in E.164-Ziffern ohne '+' um."""
    s = re.sub(r"[\s\-/().]", "", raw or "")
    if s in NOTRUF:
        raise NumberError("Notrufe sind über Tuut nicht möglich. Bitte 112 bzw. 110 über das normale Telefon wählen.")
    if s.startswith("+"):
        digits = s[1:]
    elif s.startswith("00"):
        digits = s[2:]
    elif s.startswith("0"):
        digits = default_cc + s[1:]
    else:
        raise NumberError("Bitte mit Vorwahl wählen, z. B. 030 1234567 oder +49 30 1234567.")
    if not digits.isdigit():
        raise NumberError("Die Nummer darf nur Ziffern enthalten (und am Anfang ein +).")
    if not 8 <= len(digits) <= 15:
        raise NumberError("Die Nummer ist zu kurz oder zu lang.")
    return digits


def billed_seconds(duration: int, first: int, nxt: int) -> int:
    if duration <= 0:
        return 0
    if duration <= first:
        return first
    rest = duration - first
    return first + -(-rest // nxt) * nxt


def cost_cents(duration: int, t: Tariff) -> int:
    """Kosten eines Gesprächs mit tatsächlicher Dauer `duration` (Sekunden). Unverbunden = 0."""
    billed = billed_seconds(duration, t.first, t.next)
    if billed <= 0:
        return 0
    hc = -(-(billed * t.rate_hc) // 60)       # aufrunden auf ganze Hundertstel-Cent
    return t.fee_cents + -(-hc // 100)        # aufrunden auf ganze Cent


def max_seconds(budget_cents: int, t: Tariff, cap_seconds: int) -> int:
    """Längste Gesprächsdauer, deren Kosten das Budget nicht übersteigen (0 = nicht einmal der erste Takt)."""
    if budget_cents < cost_cents(1, t):
        return 0
    lo, hi = 1, cap_seconds
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if cost_cents(mid, t) <= budget_cents:
            lo = mid
        else:
            hi = mid - 1
    return lo


def format_number(digits: str) -> str:
    return "+" + digits


def euro(cents: int) -> str:
    sign = "-" if cents < 0 else ""
    c = abs(cents)
    return f"{sign}{c // 100},{c % 100:02d} €"
