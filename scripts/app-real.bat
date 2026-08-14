@echo off
REM ============================================================
REM  TRAKTOR - prilozhenie s nastoyashchim backendom.
REM  Podnimaet identity + notifications + gateway i otkryvaet
REM  prilozhenie v Chrome. Kod podtverzhdeniya budet viden v
REM  otdelnom okne "IDENTITY" (stroka "code":"123456").
REM ============================================================
title Traktor - zapusk s backendom
call C:\Traktor\scripts\env.bat
set BIN=%OUTDIR%\_bin

echo.
echo   TRAKTOR - zapusk s nastoyashchim backendom
echo   ------------------------------------------------
echo   1) Sobiraem servisy...

if not exist "%BIN%" mkdir "%BIN%"
cd /d C:\Traktor\services\identity
go build -o "%BIN%\identity.exe" ./cmd/identity || goto err
cd /d C:\Traktor\services\notifications
go build -o "%BIN%\notifications.exe" ./cmd/notifications || goto err
cd /d C:\Traktor\services\gateway
go build -o "%BIN%\gateway.exe" ./cmd/gateway || goto err

echo   2) Gasim ostatki proshlyh zapuskov...
taskkill /f /im identity.exe >nul 2>&1
taskkill /f /im gateway.exe >nul 2>&1
taskkill /f /im notifications.exe >nul 2>&1

echo   3) Zapuskaem servisy (porty 18080-18082)...
start "IDENTITY - zdes viden kod dlya vhoda" cmd /k "set PORT=18081&& set TEST_MODE=1&& set JWT_KID=dev&& "%BIN%\identity.exe""
start "NOTIFICATIONS" cmd /k "set PORT=18082&& "%BIN%\notifications.exe""
start "GATEWAY" cmd /k "set PORT=18080&& set JWKS_URL=http://localhost:18081/.well-known/jwks.json&& set IDENTITY_URL=http://localhost:18081&& set NOTIFICATIONS_URL=http://localhost:18082&& "%BIN%\gateway.exe""

timeout /t 4 >nul

echo.
echo   ------------------------------------------------
echo   GDE VZYAT KOD: v okne "IDENTITY - zdes viden kod"
echo   posle vvoda nomera poyavitsya stroka "code":"123456"
echo   ------------------------------------------------
echo   4) Otkryvaem prilozhenie v Chrome (pervyy zapusk 1-3 min)
echo.

cd /d C:\Traktor\apps\mobile
call "%FLUTTER_BAT%" run -d chrome --dart-define=REAL_BACKEND=true --dart-define=API_BASE_URL=http://localhost:18080/v1
goto done

:err
echo.
echo   OSHIBKA sborki servisov. Zapustite check-all.bat i prishlite log.
:done
echo.
echo   Zakryvayu servisy...
taskkill /f /im identity.exe >nul 2>&1
taskkill /f /im gateway.exe >nul 2>&1
taskkill /f /im notifications.exe >nul 2>&1
pause
