@echo off
REM Odnorazovaya nastroyka tunnelya: sozdanie, konfig, DNS-zapisi.
call C:\Traktor\scripts\env.bat
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Traktor\scripts\tunnel-up.ps1 > "%OUTDIR%\tunnel-up.txt" 2>&1
echo === EXITCODE %ERRORLEVEL% === >> "%OUTDIR%\tunnel-up.txt"
