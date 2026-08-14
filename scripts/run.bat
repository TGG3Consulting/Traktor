@echo off
REM Proverka posle pravok + kommit.
call C:\Traktor\scripts\env.bat
set LOG=%OUTDIR%\final2.txt

> "%LOG%" echo === PROVERKA %DATE% %TIME% ===
>> "%LOG%" echo --- identity: build + test ---
cd /d C:\Traktor\services\identity
go build ./... >> "%LOG%" 2>&1
echo build exit %ERRORLEVEL% >> "%LOG%"
go vet ./... >> "%LOG%" 2>&1
echo vet exit %ERRORLEVEL% >> "%LOG%"
go test -count=1 ./... >> "%LOG%" 2>&1
echo test exit %ERRORLEVEL% >> "%LOG%"

>> "%LOG%" echo.
>> "%LOG%" echo --- mobile: analyze + test ---
cd /d C:\Traktor\apps\mobile
call "%FLUTTER_BAT%" analyze >> "%LOG%" 2>&1
call "%FLUTTER_BAT%" test >> "%LOG%" 2>&1
echo test exit %ERRORLEVEL% >> "%LOG%"

>> "%LOG%" echo.
>> "%LOG%" echo --- kommit ---
cd /d C:\Traktor
git add -A . >> "%LOG%" 2>&1
git commit -F C:\Traktor\scripts\_msg\10-local-prod.txt >> "%LOG%" 2>&1
git push origin main >> "%LOG%" 2>&1
echo push exit %ERRORLEVEL% >> "%LOG%"
git log --oneline -3 >> "%LOG%" 2>&1
>> "%LOG%" echo === DONE ===
