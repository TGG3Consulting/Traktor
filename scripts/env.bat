@echo off
REM Obshchaya sreda dlya vseh skriptov Traktor.
set "GOROOT=%USERPROFILE%\sdk\go"
set "PATH=%GOROOT%\bin;%USERPROFILE%\go\bin;%PATH%"
set "OUTDIR=C:\Traktor\scripts\_out"
if not exist "%OUTDIR%" mkdir "%OUTDIR%"
