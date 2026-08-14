@echo off
REM Obshchaya sreda dlya vseh skriptov Traktor.
REM
REM Zashchita ot povtornogo vyzova: ranshe kazhdyy vyzov dopisyval puti v PATH,
REM i posle neskolkih vlozhennyh vyzovov stroka prevyshala predel Windows
REM (8191 simvolov) - cmd padal s "Slishkom dlinnaya vhodnaya stroka".
set "GOROOT=%USERPROFILE%\sdk\go"
set "FLUTTER_HOME=%USERPROFILE%\sdk\flutter"
set "FLUTTER_BAT=%FLUTTER_HOME%\bin\flutter.bat"
set "OUTDIR=C:\Traktor\scripts\_out"
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

if "%TRAKTOR_ENV%"=="1" goto :eof
set "PATH=%GOROOT%\bin;%USERPROFILE%\go\bin;%FLUTTER_HOME%\bin;%PATH%"
set "TRAKTOR_ENV=1"
