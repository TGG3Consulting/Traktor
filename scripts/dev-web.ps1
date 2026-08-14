# Otladochnaya sborka prilozheniya: hodit v shlyuz napryamuyu na localhost,
# minuya homly.am. Nuzhna potomu, chto s etogo kompyutera imya homly.am poka
# vedet na staryy hosting (kesh DNS), a s telefona - kuda nado.
#
# Razdaetsya na http://localhost:18091 otdelnym konteynerom, boevaya razdacha
# (18090) pri etom ne trogaetsya.
#
# VNIMANIE: tolko latinitsa - PowerShell 5.1 chitaet .ps1 v ANSI.

$ErrorActionPreference = 'Continue'
$parts = @(
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User'),
    (Join-Path $env:USERPROFILE 'sdk\flutter\bin')
) -join ';'
$env:PATH = ($parts -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'

$flutter = Join-Path $env:USERPROFILE 'sdk\flutter\bin\flutter.bat'
$outDir  = 'C:\Traktor\apps\mobile\build\webdev'

Write-Output '--- Sborka otladochnoy versii ---'
Push-Location 'C:\Traktor\apps\mobile'
& $flutter build web --pwa-strategy=none `
    --dart-define=REAL_BACKEND=true `
    --dart-define=API_BASE_URL=http://localhost:18080/v1 `
    -o $outDir 2>&1 | Select-Object -Last 5 | ForEach-Object { "  $_" }
Pop-Location
if (-not (Test-Path "$outDir\main.dart.js")) { Write-Output '  PROVAL: sborka ne poluchilas'; exit 1 }
Write-Output '  OK: sobrano'

Write-Output '--- Razdacha na 18091 ---'
docker rm -f traktor-web-dev 2>&1 | Out-Null
docker run -d --name traktor-web-dev -p 18091:80 `
    -v "${outDir}:/usr/share/nginx/html:ro" nginx:alpine 2>&1 | ForEach-Object { "  $_" }
Start-Sleep -Seconds 3
try {
    $r = Invoke-WebRequest 'http://localhost:18091/' -UseBasicParsing -TimeoutSec 10
    if ($r.Content -match 'Traktor') { Write-Output '  OK: http://localhost:18091 otdaet prilozhenie' }
    else { Write-Output '  PROVAL: otvet bez prilozheniya' }
} catch { Write-Output "  PROVAL: $_" }
