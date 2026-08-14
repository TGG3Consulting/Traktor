@echo off
REM ============================================================
REM  TRAKTOR - podnyat vsyo i otdat naruzhu cherez homly.am
REM   api.homly.am -> shlyuz      rt.homly.am -> realtime
REM   app.homly.am -> prilozhenie
REM  Kod podtverzhdeniya pri vhode: 000000
REM ============================================================
title Traktor - zapusk boevogo rezhima
call C:\Traktor\scripts\env.bat
set BIN=%OUTDIR%\_bin
set LOG=%OUTDIR%\go-live.txt
set DATABASE_URL=postgres://traktor:traktor-local@localhost:15432/traktor?sslmode=disable
set PHONE_ENC_KEY=traktor-local-phone-key

> "%LOG%" echo === GO-LIVE %DATE% %TIME% ===

echo.
echo   1) Infrastruktura (baza, kesh, fayly, realtime, web)...
call C:\Traktor\scripts\stack-ensure.bat
if errorlevel 1 goto err

echo   2) Sborka servisov...
if not exist "%BIN%" mkdir "%BIN%"
cd /d C:\Traktor\services\identity
go build -o "%BIN%\identity.exe" ./cmd/identity >> "%LOG%" 2>&1 || goto err
cd /d C:\Traktor\services\notifications
go build -o "%BIN%\notifications.exe" ./cmd/notifications >> "%LOG%" 2>&1 || goto err
cd /d C:\Traktor\services\gateway
go build -o "%BIN%\gateway.exe" ./cmd/gateway >> "%LOG%" 2>&1 || goto err

echo   3) Sborka veb-prilozheniya pod adres api.homly.am (2-3 minuty)...
cd /d C:\Traktor\apps\mobile
call "%FLUTTER_BAT%" build web --dart-define=REAL_BACKEND=true --dart-define=API_BASE_URL=https://api.homly.am/v1 >> "%LOG%" 2>&1
if errorlevel 1 goto err

echo   4) Perezapusk servisov...
taskkill /f /im identity.exe >nul 2>&1
taskkill /f /im gateway.exe >nul 2>&1
taskkill /f /im notifications.exe >nul 2>&1
start "IDENTITY" cmd /k "set PORT=18081&& set TEST_MODE=1&& set OTP_STATIC_CODE=000000&& set JWT_KID=dev&& set DATABASE_URL=%DATABASE_URL%&& set PHONE_ENC_KEY=%PHONE_ENC_KEY%&& "%BIN%\identity.exe""
start "NOTIFICATIONS" cmd /k "set PORT=18082&& set DATABASE_URL=%DATABASE_URL%&& "%BIN%\notifications.exe""
start "GATEWAY" cmd /k "set PORT=18080&& set ALLOW_ORIGIN=https://app.homly.am&& set JWKS_URL=http://localhost:18081/.well-known/jwks.json&& set IDENTITY_URL=http://localhost:18081&& set NOTIFICATIONS_URL=http://localhost:18082&& "%BIN%\gateway.exe""
timeout /t 5 >nul

echo   5) Perezapusk razdachi prilozheniya...
docker restart traktor-web >> "%LOG%" 2>&1

echo   6) Tunnel...
taskkill /f /im cloudflared.exe >nul 2>&1
start "TUNNEL homly.am - ne zakryvayte" cmd /k ""%USERPROFILE%\sdk\cloudflared\cloudflared.exe" tunnel --config "%USERPROFILE%\.cloudflared\config.yml" run traktor"
timeout /t 12 >nul

echo   7) Proverka snaruzhi...
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Traktor\scripts\live-check.ps1 >> "%LOG%" 2>&1
type "%LOG%" | findstr /C:"OK:" /C:"PROVAL:" /C:"ITOG"

echo.
echo   ------------------------------------------------
echo   Prilozhenie:  https://app.homly.am
echo   Kod vhoda:    000000
echo   ------------------------------------------------
goto end

:err
echo.
echo   OSHIBKA. Podrobnosti: %LOG%
:end
pause
