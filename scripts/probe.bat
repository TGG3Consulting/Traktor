@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
set BASE=C:\Traktor\scripts
set OUTDIR=%BASE%\_out
if not exist "%OUTDIR%" mkdir "%OUTDIR%"
set OUT=%OUTDIR%\probe.txt

> "%OUT%" echo === TRAKTOR TOOLCHAIN PROBE ===
>> "%OUT%" echo date: %DATE% %TIME%
>> "%OUT%" echo user: %USERNAME%
>> "%OUT%" echo.

>> "%OUT%" echo --- go ---
where go >> "%OUT%" 2>&1
go version >> "%OUT%" 2>&1
go env GOPATH GOMODCACHE GOPROXY >> "%OUT%" 2>&1
>> "%OUT%" echo.

>> "%OUT%" echo --- flutter ---
where flutter >> "%OUT%" 2>&1
call flutter --version >> "%OUT%" 2>&1
>> "%OUT%" echo.

>> "%OUT%" echo --- dart ---
where dart >> "%OUT%" 2>&1
>> "%OUT%" echo.

>> "%OUT%" echo --- git ---
where git >> "%OUT%" 2>&1
git --version >> "%OUT%" 2>&1
>> "%OUT%" echo.

>> "%OUT%" echo --- docker ---
where docker >> "%OUT%" 2>&1
docker --version >> "%OUT%" 2>&1
>> "%OUT%" echo.

>> "%OUT%" echo --- winget ---
where winget >> "%OUT%" 2>&1
winget --version >> "%OUT%" 2>&1
>> "%OUT%" echo.

>> "%OUT%" echo --- node ---
where node >> "%OUT%" 2>&1
node --version >> "%OUT%" 2>&1
>> "%OUT%" echo.

>> "%OUT%" echo --- internet ---
ping -n 2 proxy.golang.org >> "%OUT%" 2>&1
>> "%OUT%" echo.

>> "%OUT%" echo --- repo git status ---
cd /d C:\Traktor
git status --short >> "%OUT%" 2>&1
git log --oneline -5 >> "%OUT%" 2>&1
>> "%OUT%" echo.

>> "%OUT%" echo === DONE ===
endlocal
