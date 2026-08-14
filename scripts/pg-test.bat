@echo off
REM Integratsionnye testy protiv nastoyashchego Postgres v Docker.
REM Podnimaet vremennyy konteyner, progonyaet testy, gasit konteyner.
call C:\Traktor\scripts\env.bat
set LOG=%OUTDIR%\pg-test.txt
set PGNAME=traktor-pg-test
set TEST_DATABASE_URL=postgres://traktor:traktor@localhost:55432/traktor?sslmode=disable

> "%LOG%" echo === Proverka demona Docker ===
docker info >nul 2>&1
if %ERRORLEVEL%==0 goto dockerok

>> "%LOG%" echo Docker ne zapushchen - zapuskaem Docker Desktop
start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
set /a DTRIES=0
:dockerwait
set /a DTRIES+=1
timeout /t 5 >nul
docker info >nul 2>&1
if %ERRORLEVEL%==0 goto dockerok
if %DTRIES% GEQ 48 goto dockerfail
goto dockerwait

:dockerfail
>> "%LOG%" echo DOCKER NE PODNYALSYA za 4 minuty
goto finish

:dockerok
>> "%LOG%" echo Docker gotov
>> "%LOG%" echo.
>> "%LOG%" echo === Postgres v Docker: start ===
docker rm -f %PGNAME% >> "%LOG%" 2>&1
docker run -d --name %PGNAME% -e POSTGRES_USER=traktor -e POSTGRES_PASSWORD=traktor -e POSTGRES_DB=traktor -p 55432:5432 postgres:16-alpine >> "%LOG%" 2>&1
echo --- exit %ERRORLEVEL% --- >> "%LOG%"

>> "%LOG%" echo.
>> "%LOG%" echo === Zhdem gotovnost bazy ===
set /a TRIES=0
:waitloop
set /a TRIES+=1
docker exec %PGNAME% pg_isready -U traktor -d traktor >nul 2>&1
if %ERRORLEVEL%==0 goto ready
if %TRIES% GEQ 40 goto notready
timeout /t 2 >nul
goto waitloop

:notready
>> "%LOG%" echo BAZA NE PODNYALAS za 80 sekund
docker logs %PGNAME% >> "%LOG%" 2>&1
goto cleanup

:ready
>> "%LOG%" echo baza gotova posle %TRIES% popytok

>> "%LOG%" echo.
>> "%LOG%" echo === identity: integration ===
cd /d C:\Traktor\services\identity
go test -tags integration -count=1 -v ./internal/store/ >> "%LOG%" 2>&1
echo --- exit %ERRORLEVEL% --- >> "%LOG%"

>> "%LOG%" echo.
>> "%LOG%" echo === notifications: integration ===
cd /d C:\Traktor\services\notifications
go test -tags integration -count=1 -v ./internal/store/ >> "%LOG%" 2>&1
echo --- exit %ERRORLEVEL% --- >> "%LOG%"

:cleanup
>> "%LOG%" echo.
>> "%LOG%" echo === Gasim konteyner ===
docker rm -f %PGNAME% >> "%LOG%" 2>&1

:finish
>> "%LOG%" echo === DONE ===
