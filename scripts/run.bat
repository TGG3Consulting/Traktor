@echo off
call C:\Traktor\scripts\env.bat
cd /d C:\Traktor
> "%OUTDIR%\commit5.txt" echo === KOMMIT %DATE% %TIME% ===
git add -A . >> "%OUTDIR%\commit5.txt" 2>&1
git commit -F C:\Traktor\scripts\_msg\13-phosphor.txt >> "%OUTDIR%\commit5.txt" 2>&1
git push origin main >> "%OUTDIR%\commit5.txt" 2>&1
git log --oneline -3 >> "%OUTDIR%\commit5.txt" 2>&1
echo === DONE === >> "%OUTDIR%\commit5.txt"
