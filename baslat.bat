@echo off
title OMNI-NEXUS APEX OS v5.0 - BIRLESIK BASLATICI
cd /d "%~dp0"
echo [*] Onceki acik Omni-Bridge oturumlari kontrol ediliyor...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe' OR Name='pwsh.exe'\" | Where-Object { $_.CommandLine -like '*omni-bridge.ps1*' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; Start-Sleep -Milliseconds 400"

if exist "C:\OtonomAsistan\Antigravity_V4_Ultra\daemon_supervisor.py" (
    echo [*] Birlesik Python Super-Beyin (:8765 + Telefon WSS :8766 + Telegram) baslatiliyor...
    start "OMNI_NEXUS_APEX" /min py "C:\OtonomAsistan\Antigravity_V4_Ultra\daemon_supervisor.py" --replace
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0omni-bridge.ps1"
if %errorlevel% neq 0 (
    echo.
    echo [HATA] Sunucu baslatilamadi. Alternatif olarak index.html aciliyor...
    start "" "%~dp0index.html"
    pause
)
