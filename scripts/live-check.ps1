# Proverka, chto kompyuter deystvitelno otdaet servisy naruzhu cherez homly.am.
$failed = $false
function Check($cond, $msg) {
    if ($cond) { Write-Output "  OK: $msg" } else { Write-Output "  PROVAL: $msg"; $script:failed = $true }
}

Write-Output "`n--- Proverka vneshnih adresov ---"

# 1. Shlyuz otvechaet po https
try {
    $h = Invoke-WebRequest 'https://api.homly.am/healthz' -UseBasicParsing -TimeoutSec 20
    Check ($h.StatusCode -eq 200) "api.homly.am/healthz -> $($h.StatusCode)"
} catch { Check $false "api.homly.am nedostupen: $($_.Exception.Message)" }

# 2. Polnyy vhod snaruzhi: kod 000000
try {
    $phone = '+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999)
    Invoke-RestMethod 'https://api.homly.am/v1/auth/otp/start' -Method Post -ContentType 'application/json' `
        -Body (@{ phone = $phone } | ConvertTo-Json) -TimeoutSec 20 | Out-Null
    $s = Invoke-RestMethod 'https://api.homly.am/v1/auth/otp/verify' -Method Post -ContentType 'application/json' `
        -Headers @{ 'Idempotency-Key' = "live-$([guid]::NewGuid())" } `
        -Body (@{ phone = $phone; code = '000000' } | ConvertTo-Json) -TimeoutSec 20
    Check ($s.accessToken -and $s.user.id) "vhod snaruzhi rabotaet, polzovatel $($s.user.id)"
} catch { Check $false "vhod snaruzhi ne proshel: $($_.Exception.Message)" }

# 3. Veb-prilozhenie otdaetsya
try {
    $a = Invoke-WebRequest 'https://app.homly.am' -UseBasicParsing -TimeoutSec 20
    Check ($a.StatusCode -eq 200 -and $a.Content -match 'Traktor') 'app.homly.am otdaet prilozhenie'
} catch { Check $false "app.homly.am nedostupen: $($_.Exception.Message)" }

# 4. Realtime
try {
    $r = Invoke-WebRequest 'https://rt.homly.am/health' -UseBasicParsing -TimeoutSec 20
    Check ($r.StatusCode -eq 200) 'rt.homly.am (realtime) otvechaet'
} catch { Check $false "rt.homly.am nedostupen: $($_.Exception.Message)" }

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: VSE RABOTAET SNARUZHI'; exit 0 }
