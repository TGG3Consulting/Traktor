@echo off
REM ============================================================
REM  TRAKTOR - prilozhenie na nastoyashchey infrastrukture.
REM  Podnimaet bazu/kesh/hranilishche/realtime v Docker, zapuskaet
REM  servisy i otkryvaet prilozhenie v Chrome.
REM  KOD PODTVERZHDENIYA PRI VHODE: 000000
REM ============================================================
title Traktor - zapusk
call C:\Traktor\scripts\env.bat
set BIN=%OUTDIR%\_bin

REM --- nastroyki lokalnogo "proda" (v oblake pridut iz Secret Manager) ---
set DATABASE_URL=postgres://traktor:traktor-local@localhost:15432/traktor?sslmode=disable
set PHONE_ENC_KEY=traktor-local-phone-key
set TEST_MODE=1
set OTP_STATIC_CODE=000000
set JWT_KID=dev

echo.
echo   1) Podnimaem infrastrukturu (Postgres, Redis, MinIO, Centrifugo)...
call C:\Traktor\scripts\stack-ensure.bat
if errorlevel 1 goto err_docker

echo   2) Sobiraem servisy...
if not exist "%BIN%" mkdir "%BIN%"
cd /d C:\Traktor\services\identity
go build -o "%BIN%\identity.exe" ./cmd/identity || goto err_build
cd /d C:\Traktor\services\notifications
go build -o "%BIN%\notifications.exe" ./cmd/notifications || goto err_build
cd /d C:\Traktor\services\gateway
go build -o "%BIN%\gateway.exe" ./cmd/gateway || goto err_build

echo   3) Gasim ostatki proshlyh zapuskov...
taskkill /f /im identity.exe >nul 2>&1
taskkill /f /im gateway.exe >nul 2>&1
taskkill /f /im notifications.exe >nul 2>&1

echo   4) Zapuskaem servisy (porty 18080-18082)...
start "IDENTITY" cmd /k "set PORT=18081&& set TEST_MODE=1&& set OTP_STATIC_CODE=000000&& set JWT_KID=dev&& set DATABASE_URL=%DATABASE_URL%&& set PHONE_ENC_KEY=%PHONE_ENC_KEY%&& "%BIN%\identity.exe""
start "NOTIFICATIONS" cmd /k "set PORT=18082&& set DATABASE_URL=%DATABASE_URL%&& "%BIN%\notifications.exe""
start "GATEWAY" cmd /k "set PORT=18080&& set JWKS_URL=http://localhost:18081/.well-known/jwks.json&& set IDENTITY_URL=http://localhost:18081&& set NOTIFICATIONS_URL=http://localhost:18082&& "%BIN%\gateway.exe""

timeout /t 5 >nul

echo.
echo   ------------------------------------------------
echo   KOD PODTVERZHDENIYA PRI VHODE:  000000
echo   Nomer telefona - lyuboy, naprimer +37491234567
echo   Dannye teper sohranyayutsya v baze i ne propadayut.
echo   ------------------------------------------------
echo   5) Otkryvaem prilozhenie v Chrome (pervyy zapusk 1-3 min)
echo.

cd /d C:\Traktor\apps\mobile
call "%FLUTTER_BAT%" run -d chrome --dart-define=REAL_BACKEND=true --dart-define=API_BASE_URL=http://localhost:18080/v1
goto done

:err_docker
echo.
echo   OSHIBKA: ne udalos podnyat Docker/bazu. Smotrite %OUTDIR%\stack.txt
goto end

:err_build
echo.
echo   OSHIBKA sborki servisov. Zapustite check-all.bat i prishlite log.
goto end

:done
echo.
echo   Zakryvayu servisy (infrastruktura v Docker prodolzhaet rabotat)...
taskkill /f /im identity.exe >nul 2>&1
taskkill /f /im gateway.exe >nul 2>&1
taskkill /f /im notifications.exe >nul 2>&1
:end
pause
