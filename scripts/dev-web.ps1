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
    --dart-define=REALTIME_URL=ws://localhost:18000/connection/websocket `
    -o $outDir 2>&1 | Select-Object -Last 5 | ForEach-Object { "  $_" }
Pop-Location
if (-not (Test-Path "$outDir\main.dart.js")) { Write-Output '  PROVAL: sborka ne poluchilas'; exit 1 }
Write-Output '  OK: sobrano'

Write-Output '--- Razdacha na 18091 ---'
docker rm -f traktor-web-dev 2>&1 | Out-Null
# Tot zhe konfig, chto i v boevoy razdache: prilozhenie hodit po adresam bez
# reshetki (TZ 4.2), i bez try_files lyuboy pryamoy adres vernul by 404.
docker run -d --name traktor-web-dev -p 18091:80 `
    -v "${outDir}:/usr/share/nginx/html:ro" `
    -v "C:\Traktor\infra\local\nginx-web.conf:/etc/nginx/conf.d/default.conf:ro" `
    --add-host "host.docker.internal:host-gateway" nginx:alpine 2>&1 | ForEach-Object { "  $_" }
Start-Sleep -Seconds 3
try {
    # Proveryaem imenno pryamoy adres: on lomalsya pri perehode na puti bez reshetki.
    $r = Invoke-WebRequest 'http://localhost:18091/home' -UseBasicParsing -TimeoutSec 10
    if ($r.Content -match 'Traktor') { Write-Output '  OK: http://localhost:18091 otdaet prilozhenie' }
    else { Write-Output '  PROVAL: otvet bez prilozheniya' }
} catch { Write-Output "  PROVAL: $_" }
