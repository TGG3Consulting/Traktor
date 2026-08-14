@echo off
REM ============================================================
REM  TRAKTOR - podnyat lokalnyy "prod": baza, kesh, hranilishche
REM  faylov, realtime. Dannye sohranyayutsya mezhdu zapuskami.
REM ============================================================
title Traktor - lokalnaya infrastruktura
call C:\Traktor\scripts\env.bat
set LOG=%OUTDIR%\stack.txt
set COMPOSE=C:\Traktor\infra\local\docker-compose.yml

echo.
echo   Podnimaem infrastrukturu Traktor...
echo   (pervyy zapusk dolgiy: kachayutsya obrazy, ~500 MB)
echo.

> "%LOG%" echo === STACK UP %DATE% %TIME% ===

REM Docker Desktop mozhet byt vyklyuchen - zapuskaem i zhdem.
docker info >nul 2>&1
if %ERRORLEVEL%==0 goto dockerok
echo   Docker ne zapushchen - zapuskayu Docker Desktop...
>> "%LOG%" echo Docker ne zapushchen - zapusk Docker Desktop
start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
set /a T=0
:wait
set /a T+=1
timeout /t 5 >nul
docker info >nul 2>&1
if %ERRORLEVEL%==0 goto dockerok
if %T% GEQ 48 goto dockerfail
goto wait
:dockerfail
echo   OSHIBKA: Docker ne podnyalsya za 4 minuty.
>> "%LOG%" echo DOCKER NE PODNYALSYA
pause
exit /b 1

:dockerok
if not exist C:\Traktor\infra\local\.env copy C:\Traktor\infra\local\.env.example C:\Traktor\infra\local\.env >nul

docker compose -f "%COMPOSE%" up -d >> "%LOG%" 2>&1
if not errorlevel 1 goto started
echo   OSHIBKA pri zapuske. Podrobnosti: %LOG%
type "%LOG%"
pause
exit /b 1

:started
>> "%LOG%" echo.
>> "%LOG%" echo --- sostoyanie ---
docker compose -f "%COMPOSE%" ps >> "%LOG%" 2>&1

echo.
echo   Gotovo. Chto zapushcheno:
echo   ------------------------------------------------
echo   Postgres + PostGIS   localhost:15432   (baza dannyh)
echo   Redis                localhost:16379   (kesh)
echo   MinIO (fayly)        localhost:19000   konsol: http://localhost:19001
echo   Centrifugo           localhost:18000   (realtime)
echo   ------------------------------------------------
echo   Dannye hranyatsya v Docker i perezhivayut perezapusk.
echo   Ostanovit: scripts\stack-down.bat
echo.
docker compose -f "%COMPOSE%" ps
echo.
pause
