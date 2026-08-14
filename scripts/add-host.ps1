# Dobavlyaet eshche odin podomen v tunnel i DNS Cloudflare.
#
# Zachem: brauzer telefona derzhit staruyu kopiyu prilozheniya (kogda-to razdacha
# otdavala ee s zapasom na 7 dney). Novyy podomen - eto drugoy origin, dlya nego
# kesha net voobshche, poetomu prilozhenie gruzitsya s nulya.
#
# Ispolzovanie: add-host.ps1 app2   (podnimet app2.homly.am -> razdacha 18090)
#
# VNIMANIE: tolko latinitsa - PowerShell 5.1 chitaet .ps1 v ANSI.

param([string]$sub = 'app2', [int]$port = 18090)

$ErrorActionPreference = 'Continue'
$domain = 'homly.am'
$name   = 'traktor'
$cf     = Join-Path $env:USERPROFILE 'sdk\cloudflared\cloudflared.exe'
$config = Join-Path $env:USERPROFILE '.cloudflared\config.yml'
$out    = 'C:\Traktor\scripts\_out'

$hostname = "$sub.$domain"
Write-Output "--- Dobavlyayu $hostname -> http://127.0.0.1:$port ---"

$lines = Get-Content $config
if ($lines -match [regex]::Escape($hostname)) {
    Write-Output '  uzhe est v konfige'
} else {
    $new = @()
    foreach ($l in $lines) {
        if ($l -match '^\s*-\s*service:\s*http_status:404') {
            $new += "  - hostname: $hostname"
            $new += "    service: http://127.0.0.1:$port"
        }
        $new += $l
    }
    $new | Set-Content -Path $config -Encoding UTF8
    Write-Output '  zapisan v konfig'
}

Write-Output '--- DNS-zapis ---'
$r = (& $cf tunnel route dns --overwrite-dns $name $hostname 2>&1) | Out-String
if ($r -match 'ERR |error=|failed') { Write-Output "  OSHIBKA: $($r.Trim())" } else { Write-Output '  ok' }

Write-Output '--- Perezapusk tunnelya ---'
Get-Process -Name cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Process -FilePath $cf -ArgumentList 'tunnel', '--config', $config, 'run', $name `
    -WindowStyle Hidden -RedirectStandardOutput "$out\tunnel.log" -RedirectStandardError "$out\tunnel.err" | Out-Null
Start-Sleep -Seconds 15

Write-Output '--- Proverka ---'
$ip = $null
try {
    $ip = (Resolve-DnsName -Name $hostname -Type A -Server '1.1.1.1' -ErrorAction Stop |
           Where-Object { $_.IPAddress } | Select-Object -First 1).IPAddress
} catch { }
if (-not $ip) { $ip = '104.21.39.15' }
$body = & curl.exe -s --max-time 25 --resolve "${hostname}:443:$ip" "https://$hostname/"
if ($body -match 'Traktor') { Write-Output "  OK: https://$hostname otdaet prilozhenie" }
else { Write-Output "  PROVAL: otvet ne pohozh na prilozhenie" }
