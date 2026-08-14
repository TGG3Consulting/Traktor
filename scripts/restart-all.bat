@echo off
REM ============================================================
REM  TRAKTOR - polnyy perezapusk s nulya.
REM  Gasit vsyo staroe, sobiraet svezhee, podnimaet zanovo
REM  i proveryaet snaruzhi. Nichego drugogo zapuskat ne nuzhno.
REM ============================================================
title Traktor - polnyy perezapusk
call C:\Traktor\scripts\env.bat
set BIN=%OUTDIR%\_bin
set LOG=%OUTDIR%\restart.txt
set DATABASE_URL=postgres://traktor:traktor-local@localhost:15432/traktor?sslmode=disable
set PHONE_ENC_KEY=traktor-local-phone-key

> "%LOG%" echo === POLNYY PEREZAPUSK %DATE% %TIME% ===

echo.
echo   [1/6] Zakryvayu vse staroe...
taskkill /f /im identity.exe >nul 2>&1
taskkill /f /im gateway.exe >nul 2>&1
taskkill /f /im notifications.exe >nul 2>&1
taskkill /f /im cloudflared.exe >nul 2>&1
taskkill /f /fi "WINDOWTITLE eq IDENTITY*" >nul 2>&1
taskkill /f /fi "WINDOWTITLE eq GATEWAY*" >nul 2>&1
taskkill /f /fi "WINDOWTITLE eq NOTIFICATIONS*" >nul 2>&1
taskkill /f /fi "WINDOWTITLE eq TUNNEL*" >nul 2>&1
taskkill /f /fi "WINDOWTITLE eq CLOUDFLARE*" >nul 2>&1
taskkill /f /fi "WINDOWTITLE eq Traktor - zapusk*" >nul 2>&1
taskkill /f /fi "WINDOWTITLE eq Traktor - demo*" >nul 2>&1
>> "%LOG%" echo staroe zakryto

echo   [2/6] Podnimayu bazu i infrastrukturu...
call C:\Traktor\scripts\stack-ensure.bat
if errorlevel 1 goto err_docker

echo   [3/6] Sobirayu servisy...
if not exist "%BIN%" mkdir "%BIN%"
cd /d C:\Traktor\services\identity
go build -o "%BIN%\identity.exe" ./cmd/identity >> "%LOG%" 2>&1 || goto err
cd /d C:\Traktor\services\notifications
go build -o "%BIN%\notifications.exe" ./cmd/notifications >> "%LOG%" 2>&1 || goto err
cd /d C:\Traktor\services\gateway
go build -o "%BIN%\gateway.exe" ./cmd/gateway >> "%LOG%" 2>&1 || goto err

echo   [4/6] Sobirayu prilozhenie (2-3 minuty)...
cd /d C:\Traktor\apps\mobile
call "%FLUTTER_BAT%" build web --pwa-strategy=none --dart-define=REAL_BACKEND=true --dart-define=API_BASE_URL=https://api.homly.am/v1 >> "%LOG%" 2>&1
if errorlevel 1 goto err
docker restart traktor-web >> "%LOG%" 2>&1

echo   [5/6] Zapuskayu servisy i tunnel...
start "IDENTITY" cmd /k "set PORT=18081&& set TEST_MODE=1&& set OTP_STATIC_CODE=000000&& set JWT_KID=dev&& set DATABASE_URL=%DATABASE_URL%&& set PHONE_ENC_KEY=%PHONE_ENC_KEY%&& "%BIN%\identity.exe""
start "NOTIFICATIONS" cmd /k "set PORT=18082&& set DATABASE_URL=%DATABASE_URL%&& "%BIN%\notifications.exe""
start "GATEWAY" cmd /k "set PORT=18080&& set ALLOW_ORIGIN=https://app.homly.am&& set JWKS_URL=http://localhost:18081/.well-known/jwks.json&& set IDENTITY_URL=http://localhost:18081&& set NOTIFICATIONS_URL=http://localhost:18082&& "%BIN%\gateway.exe""
start "TUNNEL homly.am" cmd /k ""%USERPROFILE%\sdk\cloudflared\cloudflared.exe" tunnel --config "%USERPROFILE%\.cloudflared\config.yml" run traktor"
timeout /t 14 >nul

echo   [6/6] Proveryayu snaruzhi...
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Traktor\scripts\live-check.ps1 >> "%LOG%" 2>&1
type "%LOG%" | findstr /C:"OK:" /C:"PROVAL:" /C:"ITOG"

echo.
echo   ================================================
echo   Prilozhenie: https://app.homly.am
echo   Kod vhoda:   000000
echo.
echo   Dolzhno ostatsya rovno 4 chernyh okna:
echo   IDENTITY, NOTIFICATIONS, GATEWAY, TUNNEL.
echo   Ne zakryvayte ih.
echo   ================================================
goto end

:err_docker
echo   OSHIBKA: ne podnyalsya Docker/baza. Smotrite %OUTDIR%\stack.txt
goto end
:err
echo   OSHIBKA sborki. Smotrite %LOG%
:end
echo.
pause
