"""Tests der Kernlogik (ohne Datenbank und Netzwerk): python -m unittest discover tests"""
import hashlib
import hmac
import json
import sys
import types
import unittest

sys.modules.setdefault("httpx", types.ModuleType("httpx"))  # Netzwerkbibliothek wird hier nicht gebraucht

from app import pricing, stripe_api  # noqa: E402

TAB = pricing.TariffTable.load("tarife.json")


class Rufnummern(unittest.TestCase):
    def test_formate(self):
        self.assertEqual(pricing.normalize_number("030 1234567"), "49301234567")
        self.assertEqual(pricing.normalize_number("+49 (30) 123-4567"), "49301234567")
        self.assertEqual(pricing.normalize_number("0043 1 234567"), "431234567")

    def test_notruf_und_ungueltig(self):
        for n in ("112", "110", "1 1 2"):
            with self.assertRaises(pricing.NumberError):
                pricing.normalize_number(n)
        for n in ("301234567", "+49abc1234", "0301"):
            with self.assertRaises(pricing.NumberError):
                pricing.normalize_number(n)


class Tarife(unittest.TestCase):
    def test_festnetz_und_sperren(self):
        t = TAB.match("49301234567")
        self.assertFalse(t.blocked)
        self.assertEqual(t.rate_hc, 500)
        self.assertTrue(TAB.match("491701234567").blocked)      # Mobilfunk
        self.assertTrue(TAB.match("499001234567").blocked)      # 0900
        self.assertIsNone(TAB.match("431234567"))               # Österreich: kein Preis -> gesperrt

    def test_preis_ohne_fliesskomma(self):
        self.assertEqual(pricing.parse_rate_hc("1.99"), 199)
        with self.assertRaises(ValueError):
            pricing.parse_rate_hc("1.999")


class Kosten(unittest.TestCase):
    def setUp(self):
        self.t = pricing.Tariff("49", "Test", False, "", 500, 0, 60, 60)   # 5 ct/Min, 60/60

    def test_takt(self):
        self.assertEqual(pricing.billed_seconds(0, 60, 60), 0)
        self.assertEqual(pricing.billed_seconds(1, 60, 60), 60)
        self.assertEqual(pricing.billed_seconds(61, 60, 60), 120)
        self.assertEqual(pricing.billed_seconds(61, 60, 1), 61)

    def test_kosten(self):
        self.assertEqual(pricing.cost_cents(0, self.t), 0)       # nicht verbunden = kostenlos
        self.assertEqual(pricing.cost_cents(1, self.t), 5)
        self.assertEqual(pricing.cost_cents(60, self.t), 5)
        self.assertEqual(pricing.cost_cents(61, self.t), 10)
        krumm = pricing.Tariff("1", "x", False, "", 199, 10, 60, 1)  # 1,99 ct/Min + 10 ct
        self.assertEqual(pricing.cost_cents(90, krumm), 10 + 3)  # 90 s * 1,99/60 = 2,985 -> 3 ct

    def test_reservierung_deckt_gespraech(self):
        for budget in (5, 9, 10, 99, 1000):
            s = pricing.max_seconds(budget, self.t, 4 * 3600)
            self.assertLessEqual(pricing.cost_cents(s, self.t), budget)
            if s < 4 * 3600:
                self.assertGreater(pricing.cost_cents(s + 1, self.t), budget)
        self.assertEqual(pricing.max_seconds(4, self.t, 3600), 0)

    def test_euro(self):
        self.assertEqual(pricing.euro(1234), "12,34 €")
        self.assertEqual(pricing.euro(-5), "-0,05 €")


class StripeSignatur(unittest.TestCase):
    def test_gueltig_ungueltig_alt(self):
        secret, payload = "whsec_test", json.dumps({"type": "x"}).encode()
        sig = hmac.new(secret.encode(), b"1000." + payload, hashlib.sha256).hexdigest()
        self.assertEqual(stripe_api.verify_webhook(payload, f"t=1000,v1={sig}", secret, now=1000)["type"], "x")
        with self.assertRaises(stripe_api.StripeError):
            stripe_api.verify_webhook(payload, f"t=1000,v1={'0' * 64}", secret, now=1000)
        with self.assertRaises(stripe_api.StripeError):
            stripe_api.verify_webhook(payload, f"t=1000,v1={sig}", secret, now=5000)
        with self.assertRaises(stripe_api.StripeError):
            stripe_api.verify_webhook(payload + b" ", f"t=1000,v1={sig}", secret, now=1000)


if __name__ == "__main__":
    unittest.main()
