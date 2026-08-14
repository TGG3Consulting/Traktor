# Skvoznaya proverka lokalnogo "proda": servisy rabotayut na nastoyashchey baze,
# vhod idet po fiksirovannomu kodu 000000, dannye perezhivayut perezapusk servisa.
$ErrorActionPreference = 'Stop'
$out    = 'C:\Traktor\scripts\_out'
$binDir = "$out\_bin"
$procs  = @()
$failed = $false

$env:DATABASE_URL   = 'postgres://traktor:traktor-local@localhost:15432/traktor?sslmode=disable'
$env:PHONE_ENC_KEY  = 'traktor-local-phone-key'
$env:TEST_MODE      = '1'
$env:OTP_STATIC_CODE= '000000'
$env:JWT_KID        = 'dev'

function Check($cond, $msg) {
    if ($cond) { Write-Output "  OK: $msg" } else { Write-Output "  PROVAL: $msg"; $script:failed = $true }
}

# Zapolnyaet $script:procs. Nichego ne vozvrashchaet: v PowerShell lyuboy vyvod
# funktsii popadaet v ee rezultat, i stroki logov smeshalis by so spiskom processov.
function Start-Services {
    $script:procs = @()
    $env:PORT = '18081'
    $script:procs += Start-Process -PassThru -FilePath "$binDir\identity.exe" `
        -RedirectStandardOutput "$out\s-identity.log" -RedirectStandardError "$out\s-identity.err"
    $env:PORT = '18082'
    $script:procs += Start-Process -PassThru -FilePath "$binDir\notifications.exe" `
        -RedirectStandardOutput "$out\s-notifications.log" -RedirectStandardError "$out\s-notifications.err"
    $env:PORT = '18080'
    $env:JWKS_URL = 'http://localhost:18081/.well-known/jwks.json'
    $env:IDENTITY_URL = 'http://localhost:18081'
    $env:NOTIFICATIONS_URL = 'http://localhost:18082'
    $script:procs += Start-Process -PassThru -FilePath "$binDir\gateway.exe" `
        -RedirectStandardOutput "$out\s-gateway.log" -RedirectStandardError "$out\s-gateway.err"

    foreach ($p in 18080, 18081, 18082) {
        $ok = $false
        foreach ($i in 1..40) {
            try { Invoke-WebRequest "http://localhost:$p/healthz" -TimeoutSec 2 -UseBasicParsing | Out-Null; $ok = $true; break }
            catch { Start-Sleep -Milliseconds 500 }
        }
        Check $ok "servis na portu $p podnyalsya"
    }
}

function Stop-Services {
    foreach ($p in $script:procs) {
        if ($null -ne $p -and $p.Id -and -not $p.HasExited) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
    }
    $script:procs = @()
    Start-Sleep -Seconds 1
}

try {
    Write-Output "`n--- Sborka binarnikov ---"
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    $go = Join-Path $env:USERPROFILE 'sdk\go\bin\go.exe'
    foreach ($svc in 'identity','gateway','notifications') {
        Push-Location "C:\Traktor\services\$svc"
        & $go build -o "$binDir\$svc.exe" "./cmd/$svc"
        if ($LASTEXITCODE -ne 0) { throw "sborka $svc" }
        Pop-Location
    }
    Write-Output '  sobrany'

    foreach ($n in 'identity','gateway','notifications') {
        Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    Write-Output "`n--- Zapusk servisov na nastoyashchey baze ---"
    Start-Services
    if ($failed) { throw 'servisy ne podnyalis' }

    $base  = 'http://localhost:18080'
    $phone = '+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999)

    Write-Output "`n--- 1. Vhod po fiksirovannomu kodu 000000 ---"
    Invoke-RestMethod -Uri "$base/v1/auth/otp/start" -Method Post -ContentType 'application/json' `
        -Body (@{ phone = $phone } | ConvertTo-Json) | Out-Null
    $sess = Invoke-RestMethod -Uri "$base/v1/auth/otp/verify" -Method Post -ContentType 'application/json' `
        -Headers @{ 'Idempotency-Key' = 'stack-1' } `
        -Body (@{ phone = $phone; code = '000000' } | ConvertTo-Json)
    Check ($sess.accessToken -and $sess.user.id) "vhod proshel, polzovatel $($sess.user.id)"
    $userId = $sess.user.id
    $access = $sess.accessToken

    Write-Output "`n--- 2. Zapolnyaem profil ---"
    $me = Invoke-RestMethod -Uri "$base/v1/me" -Method Patch `
        -Headers @{ Authorization = "Bearer $access"; 'Idempotency-Key' = 'stack-2' } `
        -ContentType 'application/json' `
        -Body (@{ name = 'Tigran'; city = 'Erevan'; activeRole = 'owner' } | ConvertTo-Json)
    Check ($me.name -eq 'Tigran' -and $me.activeRole -eq 'owner') 'profil sohranen'

    Write-Output "`n--- 3. Telefon v baze zashifrovan ---"
    $raw = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
        "SELECT encode(phone_enc,'hex') FROM identity.users WHERE id='$userId'"
    Check ($raw -and $raw -notmatch '3749') 'phone_enc ne soderzhit nomer otkrytym tekstom'

    Write-Output "`n--- 4. Perezapusk servisov: dannye dolzhny ostatsya ---"
    Stop-Services
    Start-Services
    if ($failed) { throw 'servisy ne podnyalis posle perezapuska' }

    Invoke-RestMethod -Uri "$base/v1/auth/otp/start" -Method Post -ContentType 'application/json' `
        -Body (@{ phone = $phone } | ConvertTo-Json) | Out-Null
    $again = Invoke-RestMethod -Uri "$base/v1/auth/otp/verify" -Method Post -ContentType 'application/json' `
        -Headers @{ 'Idempotency-Key' = 'stack-3' } `
        -Body (@{ phone = $phone; code = '000000' } | ConvertTo-Json)
    Check ($again.user.id -eq $userId) 'tot zhe polzovatel (ne sozdalsya novyy)'
    Check ($again.user.name -eq 'Tigran' -and $again.user.activeRole -eq 'owner') 'profil perezhil perezapusk'

    Write-Output "`n--- 5. Registratsiya ustroystva pishetsya v bazu ---"
    Invoke-WebRequest -Uri "$base/v1/devices" -Method Post -UseBasicParsing `
        -Headers @{ Authorization = "Bearer $($again.accessToken)"; 'Idempotency-Key' = 'stack-4' } `
        -ContentType 'application/json' `
        -Body (@{ token = "dev-$([guid]::NewGuid())"; platform = 'web'; locale = 'ru' } | ConvertTo-Json) | Out-Null
    $cnt = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
        "SELECT count(*) FROM notifications.devices WHERE user_id='$userId'"
    Check ([int]$cnt -ge 1) "ustroystv v baze: $cnt"

    Write-Output "`n--- 6. Infrastruktura otvechaet ---"
    $redis = docker exec traktor-redis redis-cli ping
    Check ($redis -match 'PONG') "Redis: $redis"
    try {
        $c = Invoke-WebRequest 'http://localhost:18000/health' -UseBasicParsing -TimeoutSec 5
        Check ($c.StatusCode -eq 200) 'Centrifugo otvechaet'
    } catch { Check $false "Centrifugo: $_" }
    try {
        $m = Invoke-WebRequest 'http://localhost:19000/minio/health/live' -UseBasicParsing -TimeoutSec 5
        Check ($m.StatusCode -eq 200) 'MinIO (hranilishche faylov) otvechaet'
    } catch { Check $false "MinIO: $_" }
}
catch {
    Write-Output "`nOSHIBKA: $_"
    $failed = $true
}
finally {
    Stop-Services
    Write-Output "`n=================================="
    if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: VSE PROVERKI PROYDENY'; exit 0 }
}
