# Tuut-Server v3 (lokal)

Matrix-Server (Konten, Chat, Anruf-Signalisierung) und Guthaben-Dienst (Guthaben,
Tarife, Stripe-Aufladung, Abrechnung), je mit eigener PostgreSQL-Datenbank.

## Starten
Docker Desktop öffnen, dann **SERVER-START.cmd** doppelklicken.

## Schlüssel eintragen
Beim ersten Start legt SERVER-START `C:\Users\<dein Name>\Tuut\einstellungen.env` an und öffnet sie im Editor
(bewusst außerhalb des Projektordners, damit sie nie hochgeladen wird):
- `STRIPE_SECRET_KEY=` Stripe-Dashboard → Entwickler → API-Schlüssel → Geheimer Schlüssel
Danach SERVER-START erneut doppelklicken.

## Preise ändern
`billing/tarife.json` bearbeiten (Cent pro Minute, Takt, Sperren). Ziele ohne Eintrag sind gesperrt.
Danach SERVER-START erneut doppelklicken.

## Handy erreicht den Server nicht
**FIREWALL-FREIGABE.cmd** mit Rechtsklick → „Als Administrator ausführen“.

## Gehört NIE ins Repository
- `synapse-data/` (Signaturschlüssel, Medien, Protokolle)

## Tests der Abrechnungslogik
`billing/tests` – laufen ohne Datenbank: `python -m unittest discover tests` im Ordner `billing`.
