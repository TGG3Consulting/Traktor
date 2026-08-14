@echo off
REM Ostanovit lokalnuyu infrastrukturu. Dannye NE udalyayutsya:
REM tomа Docker ostayutsya, pri sleduyushchem zapuske vsyo na meste.
title Traktor - ostanovka infrastruktury
call C:\Traktor\scripts\env.bat
set COMPOSE=C:\Traktor\infra\local\docker-compose.yml

echo.
echo   Ostanavlivayu infrastrukturu Traktor (dannye sohranyayutsya)...
docker compose -f "%COMPOSE%" down
echo.
echo   Gotovo. Chtoby podnyat snova: scripts\stack-up.bat
echo.
pause
