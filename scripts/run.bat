@echo off
call C:\Traktor\scripts\env.bat
cd /d C:\Traktor
> "%OUTDIR%\commit4.txt" echo === KOMMIT %DATE% %TIME% ===
git add -A . >> "%OUTDIR%\commit4.txt" 2>&1
git commit -F C:\Traktor\scripts\_msg\12-fab.txt >> "%OUTDIR%\commit4.txt" 2>&1
git push origin main >> "%OUTDIR%\commit4.txt" 2>&1
git log --oneline -2 >> "%OUTDIR%\commit4.txt" 2>&1
echo === DONE === >> "%OUTDIR%\commit4.txt"
