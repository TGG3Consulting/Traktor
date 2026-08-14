$ErrorActionPreference = 'Continue'
$out    = 'C:\Traktor\scripts\_out'
$binDir = "$out\_bin"
$procs  = @()

# Gasim ostatki predydushchih zapuskov, chtoby ne poymat chuzhoy protsess na portu
foreach ($n in 'identity','gateway','notifications') {
    Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Write-Output '=== Kto slushaet porty 8080/8081/8082/18080 ==='
Get-NetTCPConnection -State Listen -LocalPort 8080,8081,8082,18080 -ErrorAction SilentlyContinue |
    ForEach-Object {
        $pr = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        "port $($_.LocalPort) <- $($pr.ProcessName) (pid $($_.OwningProcess))"
    }

$env:TEST_MODE = '1'; $env:JWT_KID = 'smoke'; $env:PORT = '18081'
$procs += Start-Process -PassThru -FilePath "$binDir\identity.exe" `
    -RedirectStandardOutput "$out\d-identity.log" -RedirectStandardError "$out\d-identity.err"
$env:PORT = '18080'
$env:JWKS_URL = 'http://localhost:18081/.well-known/jwks.json'
$env:IDENTITY_URL = 'http://localhost:18081'
$env:NOTIFICATIONS_URL = 'http://localhost:18082'
$procs += Start-Process -PassThru -FilePath "$binDir\gateway.exe" `
    -RedirectStandardOutput "$out\d-gateway.log" -RedirectStandardError "$out\d-gateway.err"
Start-Sleep -Seconds 3

function Probe($label, $url) {
    Write-Output "`n=== $label -> $url ==="
    try {
        $r = Invoke-WebRequest -Uri $url -Method Post -UseBasicParsing -TimeoutSec 10 `
            -ContentType 'application/json' -Body '{"phone":"+37491000222"}'
        Write-Output "status: $($r.StatusCode)"
        Write-Output "ctype : $($r.Headers['Content-Type'])"
        Write-Output "body  : $($r.Content)"
    } catch {
        $resp = $_.Exception.Response
        if ($resp) {
            Write-Output "status: $([int]$resp.StatusCode)"
            $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
            Write-Output "body  : $($sr.ReadToEnd())"
        } else {
            Write-Output "isklyuchenie: $_"
        }
    }
}

Probe 'napryamuyu v identity' 'http://localhost:18081/v1/auth/otp/start'
Probe 'cherez gateway'        'http://localhost:18080/v1/auth/otp/start'

Write-Output "`n=== GET /healthz gateway ==="
(Invoke-WebRequest -Uri 'http://localhost:18080/healthz' -UseBasicParsing).StatusCode

Write-Output "`n=== log gateway ==="
Get-Content "$out\d-gateway.log" -ErrorAction SilentlyContinue
Get-Content "$out\d-gateway.err" -ErrorAction SilentlyContinue
Write-Output "`n=== log identity ==="
Get-Content "$out\d-identity.log" -ErrorAction SilentlyContinue
Get-Content "$out\d-identity.err" -ErrorAction SilentlyContinue

foreach ($p in $procs) { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } }
