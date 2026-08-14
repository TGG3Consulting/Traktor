@echo off
call C:\Traktor\scripts\env.bat
set LOG=%OUTDIR%\final2.txt

> "%LOG%" echo === PROVERKA %DATE% %TIME% ===
cd /d C:\Traktor\apps\mobile
call "%FLUTTER_BAT%" test >> "%LOG%" 2>&1
echo test exit %ERRORLEVEL% >> "%LOG%"

>> "%LOG%" echo.
>> "%LOG%" echo --- status do kommita ---
cd /d C:\Traktor
git status --short >> "%LOG%" 2>&1
>> "%LOG%" echo --- kommit ---
git add -A . >> "%LOG%" 2>&1
git commit -F C:\Traktor\scripts\_msg\10-local-prod.txt >> "%LOG%" 2>&1
echo commit exit %ERRORLEVEL% >> "%LOG%"
git push origin main >> "%LOG%" 2>&1
echo push exit %ERRORLEVEL% >> "%LOG%"
git log --oneline -3 >> "%LOG%" 2>&1
>> "%LOG%" echo === DONE ===
