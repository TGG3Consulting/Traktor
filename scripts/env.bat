@echo off
REM Obshchaya sreda dlya vseh skriptov Traktor.
REM
REM PATH sobiraetsya ZANOVO iz korotkogo nabora nuzhnyh putey, a ne dopisyvaetsya
REM k unasledovannomu. Ranshe kazhdyy vyzov udlinyal stroku, i posle desyatkov
REM zadaniy podryad ona prevyshala predel Windows (8191 simvolov) - cmd padal s
REM "Slishkom dlinnaya vhodnaya stroka". Perezapusk pomoshchnika lechil eto lish
REM do sleduyushchego nakopleniya, poetomu lechim prichinu.
set "GOROOT=%USERPROFILE%\sdk\go"
set "FLUTTER_HOME=%USERPROFILE%\sdk\flutter"
set "FLUTTER_BAT=%FLUTTER_HOME%\bin\flutter.bat"
set "OUTDIR=C:\Traktor\scripts\_out"
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

if "%TRAKTOR_ENV%"=="1" goto :eof
set "PATH=%GOROOT%\bin;%USERPROFILE%\go\bin;%FLUTTER_HOME%\bin;%SystemRoot%\system32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SystemRoot%\System32\WindowsPowerShell\v1.0;%ProgramFiles%\Git\cmd;%ProgramFiles%\Docker\Docker\resources\bin"
set "TRAKTOR_ENV=1"
