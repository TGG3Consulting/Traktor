# Proverka, chto uvedomleniya o sobytiyah zadaniy realno uhodyat v servis
# notifications (TZ 2.14). Push-provayder poka fake, poetomu smotrim po logam
# servisa: zapros na rassylku byl.
#
# VNIMANIE: tolko latinitsa - PowerShell 5.1 chitaet .ps1 v ANSI.

$ErrorActionPreference = 'Continue'
$base = 'http://127.0.0.1:18080'
$failed = $false
function Check($cond, $msg) {
    if ($cond) { Write-Output "  OK: $msg" } else { Write-Output "  PROVAL: $msg"; $script:failed = $true }
}
function Login($phone) {
    Invoke-RestMethod "$base/v1/auth/otp/start" -Method Post -ContentType 'application/json' `
        -Body (@{ phone = $phone } | ConvertTo-Json) | Out-Null
    return Invoke-RestMethod "$base/v1/auth/otp/verify" -Method Post -ContentType 'application/json' `
        -Headers @{ 'Idempotency-Key' = [guid]::NewGuid().ToString() } `
        -Body (@{ phone = $phone; code = '000000' } | ConvertTo-Json)
}
function Hdr($token) { @{ Authorization = "Bearer $token"; 'Idempotency-Key' = [guid]::NewGuid().ToString() } }

$logPath = 'C:\Traktor\scripts\_out\svc-notifications.log'
$before = if (Test-Path $logPath) { (Get-Content $logPath -ErrorAction SilentlyContinue).Count } else { 0 }

Write-Output "`n--- Scenariy: zadanie -> otklik -> vybor ---"
$client = Login ('+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999))
$owner  = Login ('+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999))

$cats = Invoke-RestMethod "$base/v1/categories?kind=work"
$cat = $cats.items | Select-Object -First 1
$draft = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{
        categoryId   = $cat.id
        title        = 'Proverka uvedomleniy'
        description  = 'Zadanie dlya proverki uvedomleniy o novyh otklikah.'
        geo          = @{ lat = 40.1872; lng = 44.5152 }
        address      = 'Erevan'
        budgetAmount = 50000
        mode         = 'fixed'
    } | ConvertTo-Json)
Invoke-RestMethod "$base/v1/jobs/$($draft.id)/publish" -Method Post -Headers (Hdr $client.accessToken) | Out-Null

$offer = Invoke-RestMethod "$base/v1/jobs/$($draft.id)/offers" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ kind = 'accept'; price = 50000 } | ConvertTo-Json)
Check ($null -ne $offer.id) 'otklik sozdan'

Invoke-RestMethod "$base/v1/offers/$($offer.id)/accept" -Method Post -Headers (Hdr $client.accessToken) | Out-Null
Start-Sleep -Seconds 2

Write-Output "`n--- Servis uvedomleniy poluchil zaprosy ---"
$after = (Get-Content $logPath -ErrorAction SilentlyContinue)
$new = $after | Select-Object -Skip $before
$notifyLines = $new | Where-Object { $_ -match 'notify|rassyl|delivered|devices' }
Check ($after.Count -gt $before) "v logah notifications poyavilis novye zapisi: $($after.Count - $before)"

# Uvedomleniya idut best-effort: provayder fake, ustroystv net, no sam vyzov
# dolzhen doyti - imenno eto i proveryaem.
$ordersLog = Get-Content 'C:\Traktor\scripts\_out\svc-orders.log' -ErrorAction SilentlyContinue
$warns = $ordersLog | Where-Object { $_ -match 'uvedomlenie ne otpravleno|otkazal' }
Check ($warns.Count -eq 0) "orders ne zhaluetsya na sboy otpravki (preduprezhdeniy: $($warns.Count))"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: UVEDOMLENIYA UHODYAT'; exit 0 }
