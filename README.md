# Tuut

Einfache, quelloffene Alternative zum klassischen Skype: Kontakte, Chats und Anrufe.
Ohne Microsoft-Konto, selbst hostbar. Grundlage: Matrix (Konten, Nachrichten, Verschlüsselung).

## Stand 0.5
- Konto, Kontakte und Kontaktanfragen
- Einzelchat; neue Chats Ende-zu-Ende-verschlüsselt (vodozemac), bestehende per Schloss umstellbar
- Sprachanrufe zwischen Tuut-Nutzern (WebRTC über Matrix), Anrufliste mit Rückruf
- Wählfeld mit Preis, Takt und Verbindungsgebühr vor dem Anruf; Notrufhinweis
- Guthaben: Aufladen über Stripe (Gutschrift nur nach bestätigter Zahlung, doppelte Meldungen ohne Doppelbuchung),
  Buchungsjournal, Reservierung vor Gesprächen, Tages- und Parallelitätslimit, gesperrte Premiumziele
- Server im Ordner `server/` (Matrix + Guthaben-Dienst), Start per `SERVER-START.cmd`
- Noch nicht enthalten: Anbindung eines Telefonie-Anbieters (Festnetz meldet „nicht freigeschaltet“),
  Wiederherstellungsschlüssel, Klingelton, Push bei geschlossener App, TURN für Anrufe über das Internet

## Bauen
Bei jedem Hochladen baut GitHub automatisch (Reiter "Actions"):
- `tuut-windows` – Windows-Programm (tuut_app.exe)
- `tuut-android` – Android-App (Tuut.apk)

## Lizenz
AGPL-3.0
