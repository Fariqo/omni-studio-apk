@echo off
chcp 65001 >nul
title OMNI-NEXUS APEX OS v6.0 - TEK PORTLU BASLATICI
cd /d "%~dp0"

set "DAEMON=C:\OtonomAsistan\Antigravity_V4_Ultra\daemon_supervisor.py"
if not exist "%DAEMON%" (
    if exist "%~dp0..\daemon_supervisor.py" set "DAEMON=%~dp0..\daemon_supervisor.py"
)

if exist "%DAEMON%" (
    echo [*] OMNI-NEXUS APEX OS v6.0 Sunucusu (:8765 + WSS :8766 + Telegram) baslatiliyor...
    start "OMNI_NEXUS_APEX_V6" /min py "%DAEMON%" --replace
    timeout /t 3 /nobreak >nul
    start "" "http://127.0.0.1:8765/"
    echo [OK] Arayuz acildi: http://127.0.0.1:8765/
    exit /b 0
)

echo [UYARI] daemon_supervisor.py bulunamadi. Yerel v6 arayuz aciliyor...
start "" "%~dp0dist\index.html"
pause
