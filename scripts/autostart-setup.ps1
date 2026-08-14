# Stavit avtozapusk stenda Traktor pri vklyuchenii kompyutera.
# Prav administratora ne trebuet: fayl kladetsya v papku avtozagruzki
# polzovatelya, udalyaetsya obychnym udaleniem fayla.
#
# VNIMANIE: tolko latinitsa - PowerShell 5.1 chitaet .ps1 v ANSI.

$startup = [Environment]::GetFolderPath('Startup')

# 1. Fonovyy pomoshchnik (stavit sebya i sam, no dubliruem dlya nadezhnosti)
$agent = Join-Path $startup 'traktor-agent.bat'
@"
@echo off
start "" /min powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Traktor\scripts\agent.ps1
"@ | Set-Content -Path $agent -Encoding ASCII

# 2. Ves stend: baza, tri servisa, tunnel
$stack = Join-Path $startup 'traktor-stack.bat'
@"
@echo off
REM Podnimaet stend Traktor cherez minutu posle vhoda v sistemu:
REM Docker uspevaet zapustitsya do togo, kak my nachnem prosit u nego bazu.
timeout /t 60 >nul
start "" /min powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Traktor\scripts\services-up.ps1
"@ | Set-Content -Path $stack -Encoding ASCII

Write-Output "avtozapusk nastroen:"
Write-Output "  $agent"
Write-Output "  $stack"
