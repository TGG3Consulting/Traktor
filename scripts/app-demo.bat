@echo off
REM ============================================================
REM  TRAKTOR - prosto posmotret prilozhenie (bez servera).
REM  Kod podtverzhdeniya pri vhode: 482915
REM ============================================================
title Traktor - demo rezhim
call C:\Traktor\scripts\env.bat

echo.
echo   TRAKTOR - demo rezhim (bez servera)
echo   ------------------------------------------------
echo   KOD PODTVERZHDENIYA PRI VHODE:  482915
echo   Nomer telefona - lyuboy, naprimer +37491234567
echo.
echo   Seychas otkroetsya Chrome s prilozheniem.
echo   Pervyy zapusk dolgiy (1-3 minuty) - eto normalno.
echo   Chtoby zakryt: vernites v eto okno i nazhmite Q.
echo   ------------------------------------------------
echo.

cd /d C:\Traktor\apps\mobile
call "%FLUTTER_BAT%" run -d chrome
pause
