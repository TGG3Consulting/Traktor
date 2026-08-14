# Skvoznoy smoke-test: gateway -> identity -> notifications.
# Podnimaet tri servisa lokalno, prohodit ves put polzovatelya cherez shlyuz
# i gasit processy. Nichego ne trebuet krome Go.
$ErrorActionPreference = 'Stop'

$root    = 'C:\Traktor'
$out     = "$root\scripts\_out"
$binDir  = "$out\_bin"
$goExe   = Join-Path $env:USERPROFILE 'sdk\go\bin\go.exe'
$procs   = @()
$failed  = $false

function Step($name) { Write-Output "`n--- $name ---" }
function Check($cond, $msg) {
    if ($cond) { Write-Output "  OK: $msg" }
    else { Write-Output "  PROVAL: $msg"; $script:failed = $true }
}

New-Item -ItemType Directory -Force -Path $binDir | Out-Null

# Porty 8080-8082 na mashine mogut byt zanyaty (Docker/WSL relay), poetomu berem
# zavedomo svobodnye 18080-18082. Zaodno gasim ostatki predydushchih zapuskov.
foreach ($n in 'identity','gateway','notifications') {
    Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

try {
    Step 'Sborka binarnikov'
    foreach ($svc in 'identity', 'gateway', 'notifications') {
        Push-Location "$root\services\$svc"
        & $goExe build -o "$binDir\$svc.exe" "./cmd/$svc"
        if ($LASTEXITCODE -ne 0) { throw "sborka $svc" }
        Pop-Location
        Write-Output "  sobran: $svc"
    }

    Step 'Zapusk servisov'
    # Windows PowerShell 5.1 ne umeet -Environment u Start-Process, poetomu
    # peremennye stavim v tekushchey sessii: dochernie processy ih nasleduyut.
    $env:TEST_MODE = '1'
    $env:JWT_KID   = 'smoke'
    $env:PORT      = '18081'
    $procs += Start-Process -PassThru -FilePath "$binDir\identity.exe" `
        -RedirectStandardOutput "$out\svc-identity.log" -RedirectStandardError "$out\svc-identity.err"

    $env:PORT = '18082'
    $procs += Start-Process -PassThru -FilePath "$binDir\notifications.exe" `
        -RedirectStandardOutput "$out\svc-notifications.log" -RedirectStandardError "$out\svc-notifications.err"

    $env:PORT              = '18080'
    $env:JWKS_URL          = 'http://localhost:18081/.well-known/jwks.json'
    $env:IDENTITY_URL      = 'http://localhost:18081'
    $env:NOTIFICATIONS_URL = 'http://localhost:18082'
    $procs += Start-Process -PassThru -FilePath "$binDir\gateway.exe" `
        -RedirectStandardOutput "$out\svc-gateway.log" -RedirectStandardError "$out\svc-gateway.err"

    # Zhdem gotovnost vseh treh
    foreach ($p in 18080, 18081, 18082) {
        $ready = $false
        foreach ($i in 1..30) {
            try {
                Invoke-WebRequest -Uri "http://localhost:$p/healthz" -TimeoutSec 2 -UseBasicParsing | Out-Null
                $ready = $true; break
            } catch { Start-Sleep -Milliseconds 500 }
        }
        Check $ready "port $p otvechaet na /healthz"
    }
    if ($failed) { throw 'servisy ne podnyalis' }

    $phone = '+37491000111'
    $base  = 'http://localhost:18080'

    Step '1. Zapros koda cherez shlyuz (publichnyy put, bez tokena)'
    $r = Invoke-RestMethod -Uri "$base/v1/auth/otp/start" -Method Post `
        -ContentType 'application/json' -Body (@{ phone = $phone } | ConvertTo-Json)
    Check ($r.channel -eq 'fake') "kanal dostavki: $($r.channel)"
    Check ($r.retryAfterSec -gt 0) "retryAfterSec: $($r.retryAfterSec)"

    Step '2. Kod iz loga identity (fake-provayder)'
    Start-Sleep -Milliseconds 300
    $code = (Get-Content "$out\svc-identity.log" -Encoding UTF8 |
             Where-Object { $_ -match '"code":"(\d{6})"' } |
             ForEach-Object { [regex]::Match($_, '"code":"(\d{6})"').Groups[1].Value } |
             Select-Object -Last 1)
    Check ($code -match '^\d{6}$') "kod polucheN: $code"

    Step '3. Nevernyy kod otklonyaetsya'
    $status = 0
    try {
        Invoke-WebRequest -Uri "$base/v1/auth/otp/verify" -Method Post -UseBasicParsing `
            -ContentType 'application/json' -Headers @{ 'Idempotency-Key' = 'smoke-1' } `
            -Body (@{ phone = $phone; code = '000000' } | ConvertTo-Json) | Out-Null
    } catch { $status = [int]$_.Exception.Response.StatusCode }
    Check ($status -eq 401) "nevernyy kod -> HTTP $status (zhdali 401)"

    Step '4. Mutatsiya bez Idempotency-Key otklonyaetsya shlyuzom'
    $status = 0
    try {
        Invoke-WebRequest -Uri "$base/v1/devices" -Method Post -UseBasicParsing `
            -ContentType 'application/json' -Body '{}' | Out-Null
    } catch { $status = [int]$_.Exception.Response.StatusCode }
    Check ($status -eq 401 -or $status -eq 400) "bez tokena/klyucha -> HTTP $status"

    Step '5. Vhod po vernomu kodu'
    $sess = Invoke-RestMethod -Uri "$base/v1/auth/otp/verify" -Method Post `
        -ContentType 'application/json' -Headers @{ 'Idempotency-Key' = 'smoke-2' } `
        -Body (@{ phone = $phone; code = $code } | ConvertTo-Json)
    Check ($sess.accessToken -and $sess.refreshToken) 'polucheny access i refresh tokeny'
    Check ($sess.user.activeRole -eq 'client') "rol po umolchaniyu: $($sess.user.activeRole)"
    $access = $sess.accessToken

    Step '6. GET /v1/me cherez shlyuz (proverka JWKS: gateway -> identity)'
    $me = Invoke-RestMethod -Uri "$base/v1/me" -Headers @{ Authorization = "Bearer $access" }
    Check ($me.phone -eq $phone) "profil otdan: $($me.phone)"

    Step '7. GET /v1/me bez tokena -> 401'
    $status = 0
    try { Invoke-WebRequest -Uri "$base/v1/me" -UseBasicParsing | Out-Null }
    catch { $status = [int]$_.Exception.Response.StatusCode }
    Check ($status -eq 401) "bez tokena -> HTTP $status"

    Step '8. PATCH /v1/me: imya i rol ispolnitelya'
    $patched = Invoke-RestMethod -Uri "$base/v1/me" -Method Patch `
        -Headers @{ Authorization = "Bearer $access"; 'Idempotency-Key' = 'smoke-3' } `
        -ContentType 'application/json' `
        -Body (@{ name = 'Tigran'; city = 'Erevan'; activeRole = 'owner' } | ConvertTo-Json)
    Check ($patched.name -eq 'Tigran' -and $patched.activeRole -eq 'owner' -and $patched.verified) `
        "profil obnovlen: $($patched.name) / $($patched.activeRole) / verified=$($patched.verified)"

    Step '9. Registratsiya push-tokena (shlyuz -> notifications, X-User-Id)'
    $resp = Invoke-WebRequest -Uri "$base/v1/devices" -Method Post -UseBasicParsing `
        -Headers @{ Authorization = "Bearer $access"; 'Idempotency-Key' = 'smoke-4' } `
        -ContentType 'application/json' `
        -Body (@{ token = 'smoke-device-1'; platform = 'android'; locale = 'hy' } | ConvertTo-Json)
    Check ($resp.StatusCode -eq 204) "ustroystvo zaregistrirovano -> HTTP $($resp.StatusCode)"

    Step '10. Rassylka pusha na zaregistrirovannoe ustroystvo'
    $notify = Invoke-RestMethod -Uri 'http://localhost:18082/internal/notify' -Method Post `
        -ContentType 'application/json' `
        -Body (@{ userId = $me.id; title = 'Novyy otklik'; body = 'Po vashemu zadaniyu' } | ConvertTo-Json)
    Check ($notify.delivered -eq 1) "dostavleno soobshcheniy: $($notify.delivered)"

    Step '11. Rotatsiya refresh-tokena'
    $s2 = Invoke-RestMethod -Uri "$base/v1/auth/refresh" -Method Post `
        -ContentType 'application/json' -Body (@{ refreshToken = $sess.refreshToken } | ConvertTo-Json)
    Check ($s2.accessToken -and $s2.refreshToken -ne $sess.refreshToken) 'vydana novaya para tokenov'
    Check ($s2.user.activeRole -eq 'owner') "rol sohranilas posle rotatsii: $($s2.user.activeRole)"

    Step '12. Povtornoe ispolzovanie starogo refresh otklonyaetsya'
    $status = 0
    try {
        Invoke-WebRequest -Uri "$base/v1/auth/refresh" -Method Post -UseBasicParsing `
            -ContentType 'application/json' -Body (@{ refreshToken = $sess.refreshToken } | ConvertTo-Json) | Out-Null
    } catch { $status = [int]$_.Exception.Response.StatusCode }
    Check ($status -eq 401) "povtor starogo refresh -> HTTP $status (zhdali 401)"

    Step '13. JWKS otdaetsya cherez shlyuz'
    $jwks = Invoke-RestMethod -Uri "$base/.well-known/jwks.json"
    Check ($jwks.keys.Count -ge 1 -and $jwks.keys[0].kid -eq 'smoke') `
        "kluchey v JWKS: $($jwks.keys.Count), kid=$($jwks.keys[0].kid)"
}
catch {
    Write-Output "`nOSHIBKA: $_"
    $failed = $true
}
finally {
    Step 'Ostanovka servisov'
    foreach ($p in $procs) {
        if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    }
    Write-Output "`n=================================="
    if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 }
    else { Write-Output 'ITOG: VSE PROVERKI PROYDENY'; exit 0 }
}
