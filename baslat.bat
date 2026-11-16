@echo off
chcp 65001 >nul
title OMNI-NEXUS APEX OS v5.0 - BIRLESIK BASLATICI
cd /d "%~dp0"
echo [*] Onceki acik Omni-Bridge oturumlari guvenle kontrol ediliyor...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'powershell.exe' -or $_.Name -eq 'pwsh.exe') -and $_.CommandLine -like '*omni-bridge.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
timeout /t 1 /nobreak >nul

if exist "C:\OtonomAsistan\Antigravity_V4_Ultra\daemon_supervisor.py" (
    echo [*] Birlesik Python Super-Beyin (:8765 + Telefon WSS :8766 + Telegram) baslatiliyor...
    start "OMNI_NEXUS_APEX" /min py "C:\OtonomAsistan\Antigravity_V4_Ultra\daemon_supervisor.py" --replace
)

echo [*] Multi-Root Omni-Bridge (:8080+) baslatiliyor...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0omni-bridge.ps1"
if %errorlevel% neq 0 (
    echo.
    echo [UYARI] Bridge portu dolu veya baslatilamadi. Ana panel aciliyor...
    start "" "http://127.0.0.1:8765/"
    pause
)
