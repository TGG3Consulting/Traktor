@echo off
REM Podnimaet infrastrukturu, esli ona eshche ne rabotaet. Bez pauz i voprosov -
REM vyzyvaetsya iz drugih skriptov.
call C:\Traktor\scripts\env.bat
set COMPOSE=C:\Traktor\infra\local\docker-compose.yml

docker info >nul 2>&1
if %ERRORLEVEL%==0 goto dockerok
start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
set /a T=0
:wait
set /a T+=1
timeout /t 5 >nul
docker info >nul 2>&1
if %ERRORLEVEL%==0 goto dockerok
if %T% GEQ 48 exit /b 1
goto wait

:dockerok
if not exist C:\Traktor\infra\local\.env copy C:\Traktor\infra\local\.env.example C:\Traktor\infra\local\.env >nul
docker compose -f "%COMPOSE%" up -d >> "%OUTDIR%\stack.txt" 2>&1

REM Zhdem gotovnost bazy - servisy bez nee ne startuyut.
set /a P=0
:pgwait
set /a P+=1
docker exec traktor-postgres pg_isready -U traktor -d traktor >nul 2>&1
if %ERRORLEVEL%==0 exit /b 0
if %P% GEQ 40 exit /b 1
timeout /t 2 >nul
goto pgwait
