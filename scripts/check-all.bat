@echo off
REM Polnaya proverka vseh Go-servisov: format, sborka, vet, testy, aktualnost go.mod.
REM -race na Windows trebuet cgo/gcc, poetomu gonka dannyh proveryaetsya v CI (Linux).
call C:\Traktor\scripts\env.bat
set LOG=%OUTDIR%\check-all.txt
set FAILED=0
> "%LOG%" echo === POLNAYA PROVERKA %DATE% %TIME% ===

call :check identity
call :check gateway
call :check notifications

>> "%LOG%" echo.
if "%FAILED%"=="0" goto ok
>> "%LOG%" echo ITOG: EST PROVALY
goto end
:ok
>> "%LOG%" echo ITOG: VSE PROVERKI PROYDENY
:end
>> "%LOG%" echo === DONE ===
exit /b

REM ---------------------------------------------------------------
:check
set SVC=%1
>> "%LOG%" echo.
>> "%LOG%" echo ==================== %SVC% ====================
cd /d C:\Traktor\services\%SVC%

>> "%LOG%" echo --- gofmt (dolzhno byt pusto) ---
gofmt -l . >> "%LOG%" 2>&1

>> "%LOG%" echo --- go build ---
go build ./... >> "%LOG%" 2>&1
if not errorlevel 1 goto build_ok
set FAILED=1
>> "%LOG%" echo PROVAL: build %SVC%
:build_ok

>> "%LOG%" echo --- go vet ---
go vet ./... >> "%LOG%" 2>&1
if not errorlevel 1 goto vet_ok
set FAILED=1
>> "%LOG%" echo PROVAL: vet %SVC%
:vet_ok

>> "%LOG%" echo --- go test ---
go test -count=1 ./... >> "%LOG%" 2>&1
if not errorlevel 1 goto test_ok
set FAILED=1
>> "%LOG%" echo PROVAL: test %SVC%
:test_ok

REM Sravnivaem go.mod/go.sum do i posle tidy: esli tidy chto-to menyaet, znachit
REM zavisimosti v repozitorii rashodyatsya s kodom (imenno eto proveryaet CI).
>> "%LOG%" echo --- go mod tidy ne menyaet go.mod/go.sum ---
copy /y go.mod "%OUTDIR%\%SVC%.go.mod.bak" >nul
copy /y go.sum "%OUTDIR%\%SVC%.go.sum.bak" >nul
go mod tidy >> "%LOG%" 2>&1
fc go.mod "%OUTDIR%\%SVC%.go.mod.bak" >nul
if errorlevel 1 goto mod_bad
fc go.sum "%OUTDIR%\%SVC%.go.sum.bak" >nul
if errorlevel 1 goto mod_bad
goto mod_ok
:mod_bad
set FAILED=1
>> "%LOG%" echo PROVAL: go mod tidy izmenil zavisimosti %SVC% - zakommitte go.mod/go.sum
:mod_ok
del /q "%OUTDIR%\%SVC%.go.mod.bak" "%OUTDIR%\%SVC%.go.sum.bak" 2>nul
exit /b
