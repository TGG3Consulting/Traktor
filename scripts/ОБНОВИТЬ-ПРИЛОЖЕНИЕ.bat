@echo off
REM ============================================================
REM  Sobiraet svezhuyu versiyu prilozheniya i vykladyvaet na
REM  https://app.homly.am
REM  Zapuskat posle togo, kak Claude napishet "gotovo, testiruy".
REM ============================================================
title Traktor - obnovlenie prilozheniya
call C:\Traktor\scripts\env.bat
set LOG=%OUTDIR%\update-app.txt

echo.
echo   Sobirayu svezhuyu versiyu prilozheniya...
echo   (2-3 minuty, ne zakryvayte okno)
echo.

cd /d C:\Traktor\apps\mobile
> "%LOG%" echo === OBNOVLENIE %DATE% %TIME% ===
call "%FLUTTER_BAT%" build web --dart-define=REAL_BACKEND=true --dart-define=API_BASE_URL=https://api.homly.am/v1 >> "%LOG%" 2>&1
if errorlevel 1 goto err

docker restart traktor-web >> "%LOG%" 2>&1

echo.
echo   ================================================
echo   GOTOVO. Otkroyte https://app.homly.am
echo.
echo   VAZHNO: brauzer mozhet pokazat staruyu versiyu.
echo   Na iPhone (Safari): potyanite stranitsu vniz
echo   dlya obnovleniya, ili zakroyte vkladku i otkroyte
echo   zanovo.
echo   ================================================
echo.
goto end

:err
echo.
echo   OSHIBKA sborki. Prishlite Claude fayl:
echo   %LOG%
:end
pause
