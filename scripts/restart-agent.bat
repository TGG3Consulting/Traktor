@echo off
REM Perezapusk fonovogo pomoshchnika, kogda zadanie zavislo.
REM Zapuskat dvoynym klikom iz papki C:\Traktor\scripts.

echo Snimaem zavisshie processy pomoshchnika...
taskkill /f /im findstr.exe  >nul 2>&1
taskkill /f /im go.exe       >nul 2>&1
taskkill /f /im powershell.exe >nul 2>&1

echo Ubiraem zavisshee zadanie iz ocheredi...
if exist "C:\Traktor\scripts\_queue\118-fix-order.bat" (
    move /y "C:\Traktor\scripts\_queue\118-fix-order.bat" "C:\Traktor\scripts\_queue\_done_118-fix-order.bat" >nul
)

echo Zapuskaem pomoshchnika zanovo...
start "" /min powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Traktor\scripts\agent.ps1
echo Gotovo. Okno mozhno zakryt.
timeout /t 5 >nul
