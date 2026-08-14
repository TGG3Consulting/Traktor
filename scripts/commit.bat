@echo off
REM Semь logicheskih kommitov po sdelannoy rabote. Push ne delaetsya.
call C:\Traktor\scripts\env.bat
set LOG=%OUTDIR%\commit.txt
set MSG=C:\Traktor\scripts\_msg
cd /d C:\Traktor

> "%LOG%" echo === KOMMITY %DATE% %TIME% ===
git config i18n.commitEncoding utf-8 >> "%LOG%" 2>&1
git config i18n.logOutputEncoding utf-8 >> "%LOG%" 2>&1

>> "%LOG%" echo.
>> "%LOG%" echo --- 1. identity ---
git add -A services/identity >> "%LOG%" 2>&1
git commit -F "%MSG%\01-identity.txt" >> "%LOG%" 2>&1

>> "%LOG%" echo --- 2. gateway ---
git add -A services/gateway >> "%LOG%" 2>&1
git commit -F "%MSG%\02-gateway.txt" >> "%LOG%" 2>&1

>> "%LOG%" echo --- 3. notifications ---
git add -A services/notifications >> "%LOG%" 2>&1
git commit -F "%MSG%\03-notifications.txt" >> "%LOG%" 2>&1

>> "%LOG%" echo --- 4. mobile ---
git add -A apps/mobile >> "%LOG%" 2>&1
git commit -F "%MSG%\04-mobile.txt" >> "%LOG%" 2>&1

>> "%LOG%" echo --- 5. ci ---
git add -A .github .gitignore >> "%LOG%" 2>&1
git commit -F "%MSG%\05-ci.txt" >> "%LOG%" 2>&1

>> "%LOG%" echo --- 6. scripts ---
git add -A scripts >> "%LOG%" 2>&1
git commit -F "%MSG%\06-scripts.txt" >> "%LOG%" 2>&1

>> "%LOG%" echo --- 7. docs ---
git add -A CONTEXT.md HANDOFF.md ORCHESTRATOR.md docs >> "%LOG%" 2>&1
git commit -F "%MSG%\07-docs.txt" >> "%LOG%" 2>&1

>> "%LOG%" echo.
>> "%LOG%" echo === ITOG: istoriya ===
git log --oneline -10 >> "%LOG%" 2>&1
>> "%LOG%" echo.
>> "%LOG%" echo === ITOG: chto ostalos nezakommichennym ===
git status --short >> "%LOG%" 2>&1
>> "%LOG%" echo === DONE ===
