# Skvoznaya proverka centra uvedomleniy (TZ 2.14) na nastoyashchey baze:
# sobytie zadaniya -> zapis v lente -> schetchik neprochitannogo -> otmetka
# prochteniya -> chuzhaya lenta zakryta.
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
function Hdr($t) { @{ Authorization = "Bearer $t"; 'Idempotency-Key' = [guid]::NewGuid().ToString() } }
function Bearer($t) { @{ Authorization = "Bearer $t" } }
function NewPhone { '+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999) }

Write-Output "`n--- 1. Novaya lenta pusta ---"
$client = Login (NewPhone)
$owner  = Login (NewPhone)

$feed = Invoke-RestMethod "$base/v1/notifications" -Headers (Bearer $client.accessToken)
Check (@($feed.items).Count -eq 0) "u novogo polzovatelya lenta pusta: $(@($feed.items).Count)"
Check ($feed.unread -eq 0) "neprochitannyh net: $($feed.unread)"

Write-Output "`n--- 2. Otklik popadaet v lentu zakazchika ---"
$cat = (Invoke-RestMethod "$base/v1/categories?kind=work").items | Select-Object -First 1
$draft = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{
        categoryId   = $cat.id
        title        = 'Vyvezti stroitelnyy musor'
        description  = 'Okolo 12 tonn, podezd so dvora, nuzhen samosval i gruzchiki.'
        geo          = @{ lat = 40.1872; lng = 44.5152 }
        address      = 'Erevan, Nor Nork'
        budgetAmount = 70000
        mode         = 'fixed'
    } | ConvertTo-Json)
$job = Invoke-RestMethod "$base/v1/jobs/$($draft.id)/publish" -Method Post -Headers (Hdr $client.accessToken)

$offer = Invoke-RestMethod "$base/v1/jobs/$($job.id)/offers" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ kind = 'accept'; price = 70000 } | ConvertTo-Json)

Start-Sleep -Milliseconds 500
$feed = Invoke-RestMethod "$base/v1/notifications" -Headers (Bearer $client.accessToken)
$first = $feed.items | Select-Object -First 1
Check (@($feed.items).Count -ge 1) "sobytie zapisano v lentu: $(@($feed.items).Count)"
Check ($feed.unread -ge 1) "schetchik neprochitannogo: $($feed.unread)"
Check ($first.kind -eq 'offer') "tip sobytiya: $($first.kind)"
Check ($first.data.route -match "/jobs/$($job.id)/offers") "perehod vedet k otklikam: $($first.data.route)"
Check ($first.read -eq $false) 'novoe sobytie ne prochitano'

Write-Output "`n--- 3. Chuzhaya lenta zakryta ---"
$foreign = Invoke-RestMethod "$base/v1/notifications" -Headers (Bearer $owner.accessToken)
$hasClientEvent = @($foreign.items | Where-Object { $_.data.route -match "/jobs/$($job.id)/offers" }).Count
Check ($hasClientEvent -eq 0) 'sobytiya zakazchika ne vidny ispolnitelyu'

Write-Output "`n--- 4. Otmetka prochteniya ---"
Invoke-RestMethod "$base/v1/notifications/read" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{ ids = @($first.id) } | ConvertTo-Json) | Out-Null
$feed = Invoke-RestMethod "$base/v1/notifications" -Headers (Bearer $client.accessToken)
$again = $feed.items | Where-Object { $_.id -eq $first.id }
Check ($again.read -eq $true) 'sobytie stalo prochitannym'

Write-Output "`n--- 5. Prochitat vse ---"
Invoke-RestMethod "$base/v1/offers/$($offer.id)/decline" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{ reason = 'nashel drugogo' } | ConvertTo-Json) | Out-Null
Start-Sleep -Milliseconds 500

$ownerFeed = Invoke-RestMethod "$base/v1/notifications" -Headers (Bearer $owner.accessToken)
Check ($ownerFeed.unread -ge 1) "ispolnitel uznal ob otkaze: $($ownerFeed.unread)"

Invoke-RestMethod "$base/v1/notifications/read" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ ids = @() } | ConvertTo-Json) | Out-Null
$ownerFeed = Invoke-RestMethod "$base/v1/notifications" -Headers (Bearer $owner.accessToken)
Check ($ownerFeed.unread -eq 0) "posle 'prochitat vse' neprochitannyh net: $($ownerFeed.unread)"
Check (@($ownerFeed.items).Count -ge 1) 'sami zapisi ostayutsya v istorii'

Write-Output "`n--- 6. V baze ---"
$cnt = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT count(*) FROM notifications.feed WHERE user_id='$($client.user.id)'"
Check ([int]$cnt -ge 1) "zapisey v baze u zakazchika: $cnt"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: CENTR UVEDOMLENIY RABOTAET'; exit 0 }
