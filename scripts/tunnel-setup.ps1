# Traktor: podgotovka Cloudflare Tunnel.
# Skachivaet cloudflared (bez prav administratora) i proveryaet, pereehal li domen.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$dir = Join-Path $env:USERPROFILE 'sdk\cloudflared'
$exe = Join-Path $dir 'cloudflared.exe'

Write-Output "=== PODGOTOVKA TUNNELYA $(Get-Date -Format 'HH:mm:ss') ==="

Write-Output "`n1) Kuda ukazyvayut NS domena homly.am:"
try {
    $ns = Resolve-DnsName -Name homly.am -Type NS -Server 1.1.1.1 -ErrorAction Stop
    $ns | Where-Object { $_.NameHost } | ForEach-Object { "   $($_.NameHost)" }
    if (($ns.NameHost -join ' ') -match 'cloudflare') {
        Write-Output '   -> DOMEN UZHE NA CLOUDFLARE'
    } else {
        Write-Output '   -> eshche starye NS, nado podozhdat (obychno 15-60 minut)'
    }
} catch {
    Write-Output "   ne udalos proverit: $_"
}

Write-Output "`n2) cloudflared:"
if (Test-Path $exe) {
    Write-Output '   uzhe skachan'
} else {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $url = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
    Write-Output '   skachivanie...'
    (New-Object System.Net.WebClient).DownloadFile($url, $exe)
    Write-Output '   gotovo'
}
& $exe --version

Write-Output "`n=== DONE ==="
