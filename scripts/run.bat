@echo off
REM Zapusk pomoshchnika + proverka, chto on ozhil.
call C:\Traktor\scripts\env.bat
del /q "%OUTDIR%\agent-alive.txt" 2>nul
start "" /min powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Traktor\scripts\agent.ps1
timeout /t 8 >nul
> "%OUTDIR%\agent-check.txt" echo === PROVERKA POMOSHCHNIKA %DATE% %TIME% ===
if exist "%OUTDIR%\agent-alive.txt" (
  echo POMOSHCHNIK RABOTAET >> "%OUTDIR%\agent-check.txt"
  type "%OUTDIR%\agent-alive.txt" >> "%OUTDIR%\agent-check.txt"
) else (
  echo NE ZAPUSTILSYA >> "%OUTDIR%\agent-check.txt"
  if exist "%OUTDIR%\agent-error.txt" type "%OUTDIR%\agent-error.txt" >> "%OUTDIR%\agent-check.txt"
)
>> "%OUTDIR%\agent-check.txt" echo --- protsessy powershell ---
tasklist /fi "imagename eq powershell.exe" >> "%OUTDIR%\agent-check.txt" 2>&1
>> "%OUTDIR%\agent-check.txt" echo === DONE ===
