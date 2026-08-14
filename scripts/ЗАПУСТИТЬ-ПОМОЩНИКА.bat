@echo off
REM ============================================================
REM  Zapuskaet fonovogo pomoshchnika Traktor.
REM  Posle etogo Claude sam sobiraet, testiruet i perezapuskaet
REM  vsyo nuzhnoe - bez vashih klikov.
REM  Zapustit nuzhno odin raz: dalshe on podnimaetsya sam pri
REM  vklyuchenii kompyutera.
REM ============================================================
title Traktor - pomoshchnik
echo.
echo   Zapuskayu fonovogo pomoshchnika...
start "" /min powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Traktor\scripts\agent.ps1
timeout /t 5 >nul
if exist C:\Traktor\scripts\_out\agent-alive.txt (
  echo.
  echo   GOTOVO. Pomoshchnik rabotaet v fone, okon ne budet.
  echo   Teper mozhno zakryt eto okno.
) else (
  echo.
  echo   Ne udalos zapustit. Napishite ob etom Claude.
)
echo.
pause
