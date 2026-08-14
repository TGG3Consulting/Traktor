@echo off
REM Obshchaya sreda dlya vseh skriptov Traktor.
set "GOROOT=%USERPROFILE%\sdk\go"
set "FLUTTER_HOME=%USERPROFILE%\sdk\flutter"
set "FLUTTER_BAT=%FLUTTER_HOME%\bin\flutter.bat"
set "PATH=%GOROOT%\bin;%USERPROFILE%\go\bin;%FLUTTER_HOME%\bin;%PATH%"
set "OUTDIR=C:\Traktor\scripts\_out"
if not exist "%OUTDIR%" mkdir "%OUTDIR%"
