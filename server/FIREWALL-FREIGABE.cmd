@echo off
title Tuut - Firewall-Freigabe fuer das Handy
net session >nul 2>nul
if errorlevel 1 (
  echo Bitte diese Datei mit Rechtsklick und "Als Administrator ausfuehren" starten.
  pause
  exit /b 1
)
netsh advfirewall firewall delete rule name="Tuut Server" >nul 2>nul
netsh advfirewall firewall add rule name="Tuut Server" dir=in action=allow protocol=TCP localport=8008,8787 remoteip=localsubnet profile=any
if errorlevel 1 (
  echo FEHLER. Bitte ein Foto dieses Fensters schicken.
  pause
  exit /b 1
)
echo.
echo Freigabe eingerichtet: Ports 8008 und 8787, nur fuer Geraete im selben Netz.
echo Hinweis: In oeffentlichen WLANs den Server besser nicht laufen lassen.
pause
