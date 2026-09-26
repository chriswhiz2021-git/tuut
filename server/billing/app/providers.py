"""Telefonie-Anbieter (Festnetz). Umschalten über TELEFONIE_ANBIETER in einstellungen.env.

Stand dieser Version: Es ist noch KEIN Anbieter angebunden. Die konkrete Anbindung
(Telnyx oder Zadarma) wird erst eingebaut, wenn der Anbieter feststeht und seine
aktuelle Schnittstelle geprüft ist. Bis dahin lehnt der Dienst Festnetzgespräche
mit einer klaren Meldung ab – Guthaben wird dabei nie belastet.
"""
from __future__ import annotations

import os

UNTERSTUETZT: dict[str, object] = {}   # z. B. {"telnyx": TelnyxAdapter} – folgt


def status() -> tuple[bool, str]:
    name = os.environ.get("TELEFONIE_ANBIETER", "aus").strip().lower()
    if name in ("", "aus", "none", "off"):
        return False, "Festnetz ist noch nicht freigeschaltet: Es ist kein Telefonie-Anbieter eingerichtet."
    if name not in UNTERSTUETZT:
        return False, f"Telefonie-Anbieter '{name}' wird in dieser Version noch nicht unterstützt."
    return True, name
