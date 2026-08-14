# Traktor: sozdanie i zapusk Cloudflare Tunnel.
# Posle etogo kompyuter Tigrana otdaet naruzhu po https:
#   api.homly.am -> shlyuz (localhost:18080)
#   rt.homly.am  -> Centrifugo (localhost:18000)
#   app.homly.am -> veb-prilozhenie (localhost:18090)
# Pereezd v oblako = izmenit adresa v etom fayle, prilozhenie ne menyaetsya.
$ErrorActionPreference = 'Stop'

$cf      = Join-Path $env:USERPROFILE 'sdk\cloudflared\cloudflared.exe'
$cfDir   = Join-Path $env:USERPROFILE '.cloudflared'
$config  = Join-Path $cfDir 'config.yml'
$name    = 'traktor'
$domain  = 'homly.am'

Write-Output "=== TUNNEL $(Get-Date -Format 'HH:mm:ss') ==="

if (-not (Test-Path (Join-Path $cfDir 'cert.pem'))) {
    throw 'net cert.pem - snachala nuzhna avtorizatsiya (cloudflared tunnel login)'
}

Write-Output "`n1) Tunnel '$name':"
$list = & $cf tunnel list 2>&1 | Out-String
if ($list -match "\s$name\s") {
    Write-Output '   uzhe sozdan'
} else {
    & $cf tunnel create $name 2>&1 | ForEach-Object { "   $_" }
}

# Nahodim UUID i fayl s uchetnymi dannymi tunnelya.
$info = & $cf tunnel list --output json 2>$null | ConvertFrom-Json
$tunnel = $info | Where-Object { $_.name -eq $name } | Select-Object -First 1
if (-not $tunnel) { throw "tunnel $name ne nayden posle sozdaniya" }
$uuid = $tunnel.id
$credFile = Join-Path $cfDir "$uuid.json"
Write-Output "   id: $uuid"

Write-Output "`n2) Konfiguratsiya $config"
@"
# Konfiguratsiya tunnelya Traktor. Sgenerirovana scripts\tunnel-up.ps1.
tunnel: $uuid
credentials-file: $credFile

# Kazhdyy podomen vedet na svoy lokalnyy servis. Pri pereezde v oblako
# menyaetsya tolko service-adres (ili tunnel snosimtsya, a DNS smotrit v Cloud Run).
ingress:
  - hostname: api.$domain
    service: http://localhost:18080
  - hostname: rt.$domain
    service: http://localhost:18000
    originRequest:
      noTLSVerify: true
  - hostname: app.$domain
    service: http://localhost:18090
  - service: http_status:404
"@ | Set-Content -Path $config -Encoding UTF8
Write-Output '   zapisana'

Write-Output "`n3) DNS-zapisi v Cloudflare:"
# cloudflared pishet informatsionnye soobshcheniya v stderr, poetomu na vremya
# etogo bloka otklyuchaem ostanovku po oshibke - inache skript padaet na uspehe.
$ErrorActionPreference = 'Continue'
foreach ($h in "api.$domain", "rt.$domain", "app.$domain") {
    $out = (& $cf tunnel route dns --overwrite-dns $name $h 2>&1) | Out-String
    if ($out -match 'ERR |error=|failed') { Write-Output "   $h -> OSHIBKA: $($out.Trim())" }
    else { Write-Output "   $h -> ok" }
}

Write-Output "`n4) Proverka konfiguratsii:"
(& $cf tunnel ingress validate --config $config 2>&1) | ForEach-Object { "   $_" }

Write-Output "`n5) Marshruty tunnelya:"
(& $cf tunnel info $name 2>&1) | Select-Object -First 6 | ForEach-Object { "   $_" }

Write-Output "`n=== GOTOVO. Zapusk tunnelya: scripts\tunnel-run.bat ==="
