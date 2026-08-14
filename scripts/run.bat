@echo off
call C:\Traktor\scripts\env.bat
set LOG=%OUTDIR%\commit3.txt
cd /d C:\Traktor
> "%LOG%" echo === KOMMIT %DATE% %TIME% ===
git add -A . >> "%LOG%" 2>&1
git commit -F C:\Traktor\scripts\_msg\11-tunnel.txt >> "%LOG%" 2>&1
git push origin main >> "%LOG%" 2>&1
echo push exit %ERRORLEVEL% >> "%LOG%"
git log --oneline -3 >> "%LOG%" 2>&1
>> "%LOG%" echo === DONE ===
