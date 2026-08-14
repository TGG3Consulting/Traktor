@echo off
call C:\Traktor\scripts\env.bat
set MSG=C:\Traktor\scripts\_msg
set LOG=%OUTDIR%\commit2.txt
cd /d C:\Traktor

> "%LOG%" echo === KOMMIT 2 %DATE% %TIME% ===
REM Imya fayla instruktsii na kirillitse - dobavlyaem vsyo srazu iz kornya.
git add -A . >> "%LOG%" 2>&1
git commit -F "%MSG%\09-launch.txt" >> "%LOG%" 2>&1

>> "%LOG%" echo.
>> "%LOG%" echo === PUSH ===
git push origin main >> "%LOG%" 2>&1
echo --- exit %ERRORLEVEL% --- >> "%LOG%"
>> "%LOG%" echo.
git log --oneline -3 >> "%LOG%" 2>&1
>> "%LOG%" echo --- ostalos nezakommichennym ---
git status --short >> "%LOG%" 2>&1
>> "%LOG%" echo === DONE ===
