@echo off
REM Sborka i testy odnogo Go-servisa. Argument %1 = imya servisa.
call C:\Traktor\scripts\env.bat
set SVC=%1
if "%SVC%"=="" set SVC=identity
set LOG=%OUTDIR%\go-%SVC%.txt

cd /d C:\Traktor\services\%SVC%

> "%LOG%" echo === %SVC%: go mod tidy ===
go mod tidy >> "%LOG%" 2>&1
echo --- exit %ERRORLEVEL% --- >> "%LOG%"

>> "%LOG%" echo.
>> "%LOG%" echo === %SVC%: go build ./... ===
go build ./... >> "%LOG%" 2>&1
echo --- exit %ERRORLEVEL% --- >> "%LOG%"

>> "%LOG%" echo.
>> "%LOG%" echo === %SVC%: go vet ./... ===
go vet ./... >> "%LOG%" 2>&1
echo --- exit %ERRORLEVEL% --- >> "%LOG%"

>> "%LOG%" echo.
>> "%LOG%" echo === %SVC%: go test ./... ===
go test ./... >> "%LOG%" 2>&1
echo --- exit %ERRORLEVEL% --- >> "%LOG%"

>> "%LOG%" echo.
>> "%LOG%" echo === DONE ===
