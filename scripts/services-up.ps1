# Podnimaet ves lokalnyy "prod": bazu, tri Go-servisa i tunnel Cloudflare.
# Vsyo v fone, bez okon: pomoshchnik vypolnyaet etot skript i ne blokiruetsya.
#
# VNIMANIE: tolko latinitsa - PowerShell 5.1 chitaet .ps1 v ANSI.

$ErrorActionPreference = 'Continue'

# Sobiraem PATH zanovo iz sistemnyh znacheniy i ubiraem povtory. Unasledovannyy
# PATH mog byt razdut proshlymi vyzovami env.bat do predela Windows (8191), i
# togda lyubaya zapushchennaya komanda padaet s "Slishkom dlinnaya vhodnaya stroka".
$parts = @(
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User'),
    (Join-Path $env:USERPROFILE 'sdk\go\bin'),
    (Join-Path $env:USERPROFILE 'go\bin'),
    (Join-Path $env:USERPROFILE 'sdk\flutter\bin')
) -join ';'
$env:PATH = ($parts -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'

$out = 'C:\Traktor\scripts\_out'
$bin = "$out\_bin"
$go  = Join-Path $env:USERPROFILE 'sdk\go\bin\go.exe'
$cf  = Join-Path $env:USERPROFILE 'sdk\cloudflared\cloudflared.exe'
$cfg = Join-Path $env:USERPROFILE '.cloudflared\config.yml'
New-Item -ItemType Directory -Force -Path $bin | Out-Null

$db  = 'postgres://traktor:traktor-local@localhost:15432/traktor?sslmode=disable'
$key = 'traktor-local-phone-key'

Write-Output '--- 1. Baza i infrastruktura ---'
$compose = 'C:\Traktor\infra\local\docker-compose.yml'
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output '  Docker ne zapushchen - podnimayu Docker Desktop'
    Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe' -ErrorAction SilentlyContinue
    foreach ($i in 1..48) {
        Start-Sleep -Seconds 5
        docker info 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { break }
    }
}
if ($LASTEXITCODE -ne 0) { Write-Output '  PROVAL: Docker ne podnyalsya'; exit 1 }

if (-not (Test-Path 'C:\Traktor\infra\local\.env')) {
    Copy-Item 'C:\Traktor\infra\local\.env.example' 'C:\Traktor\infra\local\.env'
}
docker compose -f $compose up -d 2>&1 | ForEach-Object { "    $_" }

$pg = $false
foreach ($i in 1..40) {
    docker exec traktor-postgres pg_isready -U traktor -d traktor 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $pg = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $pg) { Write-Output '  PROVAL: baza ne otvechaet'; exit 1 }
Write-Output '  OK: baza gotova'

Write-Output '--- 2. Sborka servisov ---'
foreach ($svc in 'identity','notifications','catalog','orders','media','gateway') {
    Push-Location "C:\Traktor\services\$svc"
    & $go build -o "$bin\$svc.exe" "./cmd/$svc" 2>&1 | ForEach-Object { "    $_" }
    if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Output "  PROVAL: sborka $svc"; exit 1 }
    Pop-Location
}
Write-Output '  OK: sobrany'

Write-Output '--- 3. Gasim staroe ---'
foreach ($n in 'identity','notifications','catalog','orders','media','gateway') {
    Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 1

Write-Output '--- 4. Zapusk servisov v fone ---'
# Peremennye okruzheniya stavim pered kazhdym zapuskom: Start-Process peredaet
# dochernemu processu okruzhenie roditelya (parametra -Environment v PS 5.1 net).
$env:DATABASE_URL = $db
$env:PHONE_ENC_KEY = $key

$env:PORT = '18081'; $env:TEST_MODE = '1'; $env:OTP_STATIC_CODE = '000000'; $env:JWT_KID = 'dev'
Start-Process -FilePath "$bin\identity.exe" -WindowStyle Hidden `
    -RedirectStandardOutput "$out\svc-identity.log" -RedirectStandardError "$out\svc-identity.err" | Out-Null

$env:PORT = '18082'
Start-Process -FilePath "$bin\notifications.exe" -WindowStyle Hidden `
    -RedirectStandardOutput "$out\svc-notifications.log" -RedirectStandardError "$out\svc-notifications.err" | Out-Null

$env:PORT = '18083'
Start-Process -FilePath "$bin\catalog.exe" -WindowStyle Hidden `
    -RedirectStandardOutput "$out\svc-catalog.log" -RedirectStandardError "$out\svc-catalog.err" | Out-Null

$env:PORT = '18084'
# orders soobshchaet notifications o sobytiyah, beret imena uchastnikov u identity
# i proveryaet tehniku v otklikah u catalog
$env:NOTIFICATIONS_URL = 'http://127.0.0.1:18082'
$env:IDENTITY_URL = 'http://127.0.0.1:18081'
$env:CATALOG_URL = 'http://127.0.0.1:18083'
Start-Process -FilePath "$bin\orders.exe" -WindowStyle Hidden `
    -RedirectStandardOutput "$out\svc-orders.log" -RedirectStandardError "$out\svc-orders.err" | Out-Null

# media razdaet vremennye ssylki na zagruzku foto v MinIO
$env:PORT = '18085'
$env:S3_ENDPOINT = '127.0.0.1:19000'
$env:S3_ACCESS_KEY = 'traktor'
$env:S3_SECRET_KEY = 'traktor-local-secret'
$env:S3_BUCKET = 'traktor-media'
$env:MEDIA_PUBLIC_URL = 'http://127.0.0.1:19000/traktor-media'
Start-Process -FilePath "$bin\media.exe" -WindowStyle Hidden `
    -RedirectStandardOutput "$out\svc-media.log" -RedirectStandardError "$out\svc-media.err" | Out-Null

$env:PORT = '18080'
# Krome boevogo adresa razreshaem lokalnuyu razdachu: po ney idet otladka
# s etogo kompyutera, poka domashniy router otdaet staryy adres homly.am.
$env:ALLOW_ORIGIN = 'https://app.homly.am,https://app2.homly.am,http://localhost:18090,http://localhost:18091'
# Na lokalnom stende vse proverki idut s odnogo IP, i boevoy limit v 100
# zaprosov na minutu ostanavlivaet ih na polputi. Sam limit ostaetsya v boyu -
# menyaem tolko lokalnoe znachenie.
$env:RATE_LIMIT = '5000'
$env:JWKS_URL = 'http://127.0.0.1:18081/.well-known/jwks.json'
$env:IDENTITY_URL = 'http://127.0.0.1:18081'
$env:NOTIFICATIONS_URL = 'http://127.0.0.1:18082'
$env:CATALOG_URL = 'http://127.0.0.1:18083'
$env:ORDERS_URL = 'http://127.0.0.1:18084'
$env:MEDIA_URL = 'http://127.0.0.1:18085'
Start-Process -FilePath "$bin\gateway.exe" -WindowStyle Hidden `
    -RedirectStandardOutput "$out\svc-gateway.log" -RedirectStandardError "$out\svc-gateway.err" | Out-Null

foreach ($p in 18081, 18082, 18083, 18084, 18085, 18080) {
    $ok = $false
    foreach ($i in 1..40) {
        try { Invoke-WebRequest "http://127.0.0.1:$p/healthz" -TimeoutSec 2 -UseBasicParsing | Out-Null; $ok = $true; break }
        catch { Start-Sleep -Milliseconds 500 }
    }
    if ($ok) { Write-Output "  OK: port $p otvechaet" } else { Write-Output "  PROVAL: port $p molchit" }
}

Write-Output '--- 5. Tunnel ---'
# Cloudflared hodit na origin po imeni localhost i pervym probuet IPv6 (::1),
# a Go-servisy slushayut IPv4 - poetomu v konfige dolzhen byt 127.0.0.1.
if (Test-Path $cfg) {
    $c = Get-Content $cfg -Raw
    if ($c -match 'localhost') {
        ($c -replace 'http://localhost:', 'http://127.0.0.1:') | Set-Content -Path $cfg -Encoding UTF8
        Write-Output '  konfig tunnelya: localhost -> 127.0.0.1 (pochinka IPv6)'
        Get-Process -Name cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}
if (-not (Get-Process -Name cloudflared -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $cf -ArgumentList 'tunnel', '--config', $cfg, 'run', 'traktor' `
        -WindowStyle Hidden -RedirectStandardOutput "$out\tunnel.log" -RedirectStandardError "$out\tunnel.err" | Out-Null
    Write-Output '  tunnel zapushchen v fone'
    Start-Sleep -Seconds 12
} else {
    Write-Output '  tunnel uzhe rabotaet'
}

Write-Output '--- 6. Proverka snaruzhi ---'
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Traktor\scripts\live-check.ps1
