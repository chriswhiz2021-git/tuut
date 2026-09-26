@echo off
setlocal
title Tuut-Server
cd /d "%~dp0"

where docker >nul 2>nul
if errorlevel 1 (
  echo Docker Desktop fehlt. Bitte installieren, starten und diese Datei erneut starten.
  goto fail
)
docker info >nul 2>nul
if errorlevel 1 (
  echo Docker Desktop laeuft nicht. Bitte Docker Desktop oeffnen,
  echo warten bis "Engine running" steht, dann diese Datei erneut starten.
  goto fail
)

rem Einstellungen mit Schluesseln liegen ausserhalb des Projektordners (nie hochladen!).
set "TUUT_EINSTELLUNGEN=%USERPROFILE%\Tuut\einstellungen.env"
if not exist "%USERPROFILE%\Tuut" mkdir "%USERPROFILE%\Tuut"
if not exist "%TUUT_EINSTELLUNGEN%" (
  copy "einstellungen.beispiel.env" "%TUUT_EINSTELLUNGEN%" >nul
  if errorlevel 1 goto fail
  echo Einstellungsdatei angelegt: %TUUT_EINSTELLUNGEN%
  echo Sie oeffnet sich jetzt im Editor - dort den Stripe-Schluessel eintragen und speichern.
  start "" notepad "%TUUT_EINSTELLUNGEN%"
)
if not exist "synapse-data\tuut.local.signing.key" (
  docker compose run --rm synapse generate
  if errorlevel 1 goto fail
)
copy /y "synapse\homeserver.tuut-dev.yaml" "synapse-data\homeserver.yaml" >nul
if errorlevel 1 goto fail

echo Starte Server - beim ersten Mal dauert das einige Minuten ...
docker compose up -d --build
if errorlevel 1 goto fail

echo Warte auf Matrix-Server ...
set /a tries=0
:wait_matrix
curl.exe -s -o nul http://localhost:8008/health
if not errorlevel 1 goto matrix_ok
set /a tries+=1
if %tries% geq 90 (
  echo Matrix-Server startet nicht innerhalb von 3 Minuten.
  goto fail
)
timeout /t 2 /nobreak >nul
goto wait_matrix
:matrix_ok

echo Warte auf Guthaben-Dienst ...
set /a tries=0
:wait_billing
curl.exe -s -o nul http://localhost:8787/health
if not errorlevel 1 goto billing_ok
set /a tries+=1
if %tries% geq 90 (
  echo Guthaben-Dienst startet nicht innerhalb von 3 Minuten.
  echo Details: docker compose logs billing
  goto fail
)
timeout /t 2 /nobreak >nul
goto wait_billing
:billing_ok

echo.
echo ==============================================================
echo   Tuut-Server laeuft (Matrix + Guthaben).
echo.
echo   Windows-Programm auf diesem PC: nichts eintragen noetig.
echo.
echo   Handy im selben WLAN - diese Adresse in der App eintragen:
for /f %%a in ('powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp).IPAddress"') do echo        %%a
echo.
echo   Test am Handy: im Browser http://ADRESSE:8008 oeffnen,
echo   dort muss "It works!" stehen.
echo ==============================================================
echo.
echo Einstellungen (Stripe usw.): %TUUT_EINSTELLUNGEN%
echo Nach Aenderungen dort diese Datei erneut doppelklicken.
echo.
echo Dieses Fenster kann offen bleiben oder geschlossen werden.
pause
exit /b 0

:fail
echo.
echo FEHLER. Bitte ein Foto dieses Fensters schicken.
pause
exit /b 1
