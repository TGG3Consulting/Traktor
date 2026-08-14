@echo off
REM Proverka klientskoy chasti: pub get, gen-l10n, analyze, test.
set "FLUTTER=%USERPROFILE%\sdk\flutter\bin\flutter.bat"
set "DART=%USERPROFILE%\sdk\flutter\bin\dart.bat"
set OUTDIR=C:\Traktor\scripts\_out
if not exist "%OUTDIR%" mkdir "%OUTDIR%"
set LOG=%OUTDIR%\flutter-check.txt

> "%LOG%" echo === PROVERKA KLIENTA %DATE% %TIME% ===

>> "%LOG%" echo.
>> "%LOG%" echo ==================== design_system ====================
cd /d C:\Traktor\packages\design_system
call "%FLUTTER%" pub get >> "%LOG%" 2>&1
call "%FLUTTER%" analyze >> "%LOG%" 2>&1
call "%FLUTTER%" test >> "%LOG%" 2>&1

>> "%LOG%" echo.
>> "%LOG%" echo ==================== api_client ====================
cd /d C:\Traktor\packages\api_client
call "%DART%" pub get >> "%LOG%" 2>&1
call "%DART%" analyze >> "%LOG%" 2>&1

>> "%LOG%" echo.
>> "%LOG%" echo ==================== apps/mobile ====================
cd /d C:\Traktor\apps\mobile
call "%FLUTTER%" pub get >> "%LOG%" 2>&1
call "%FLUTTER%" gen-l10n >> "%LOG%" 2>&1
call "%FLUTTER%" analyze >> "%LOG%" 2>&1
call "%FLUTTER%" test >> "%LOG%" 2>&1

>> "%LOG%" echo.
>> "%LOG%" echo === DONE ===
