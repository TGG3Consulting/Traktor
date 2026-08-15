# Skvoznaya proverka sporov (TZ 4.1) na nastoyashchey baze:
# otkrytie -> zamorozka ocenok -> ochered moderacii -> reshenie s obosnovaniem.
#
# Fayl v UTF-8 s BOM: v nem est russkiy tekst zhaloby i resheniya.

$ErrorActionPreference = 'Continue'
$base = 'http://127.0.0.1:18080'
$failed = $false
function Check($cond, $msg) {
    if ($cond) { Write-Output "  OK: $msg" } else { Write-Output "  PROVAL: $msg"; $script:failed = $true }
}
function Login($phone) {
    Invoke-RestMethod "$base/v1/auth/otp/start" -Method Post -ContentType 'application/json; charset=utf-8' `
        -Body (@{ phone = $phone } | ConvertTo-Json) | Out-Null
    return Invoke-RestMethod "$base/v1/auth/otp/verify" -Method Post -ContentType 'application/json; charset=utf-8' `
        -Headers @{ 'Idempotency-Key' = [guid]::NewGuid().ToString() } `
        -Body (@{ phone = $phone; code = '000000' } | ConvertTo-Json)
}
function Hdr($t) { @{ Authorization = "Bearer $t"; 'Idempotency-Key' = [guid]::NewGuid().ToString() } }
function Bearer($t) { @{ Authorization = "Bearer $t" } }
function NewPhone { '+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999) }

# Telefon moderatora zadan v services-up.ps1 (MODERATOR_PHONES).
$moder = Login '+37490000001'
$client = Login (NewPhone)
$owner  = Login (NewPhone)

Write-Output "`n--- 1. Dovodim sdelku do raboty ---"
$cat = (Invoke-RestMethod "$base/v1/categories?kind=work").items | Select-Object -First 1
$d = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{
        categoryId = $cat.id
        title = 'Transheya 40 m dlya proverki sporov'
        description = 'Zadanie, na kotorom proveryaem razbor spora mezhdu storonami.'
        geo = @{ lat = 40.1872; lng = 44.5152 }
        address = 'Erevan, Avan'
        budgetAmount = 90000
        mode = 'fixed'
    } | ConvertTo-Json)
$job = Invoke-RestMethod "$base/v1/jobs/$($d.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
$offer = Invoke-RestMethod "$base/v1/jobs/$($job.id)/offers" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{ kind = 'accept'; price = 90000 } | ConvertTo-Json)
Invoke-RestMethod "$base/v1/offers/$($offer.id)/accept" -Method Post -Headers (Hdr $client.accessToken) | Out-Null
$deal = Invoke-RestMethod "$base/v1/jobs/$($job.id)/deal" -Method Post -Headers (Hdr $client.accessToken)

Write-Output "`n--- 2. Do nachala raboty spora net ---"
try {
    Invoke-RestMethod "$base/v1/deals/$($deal.id)/dispute" -Method Post -Headers (Hdr $client.accessToken) `
        -ContentType 'application/json; charset=utf-8' `
        -Body (@{ reason = 'Мне кажется, он не приедет вовремя на объект' } | ConvertTo-Json) | Out-Null
    Check $false 'do vyezda sdelku otmenyayut, a ne sporyat'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 409) 'do nachala raboty spor otklonen (409)'
}

foreach ($step in @('on_the_way', 'in_progress')) {
    Invoke-RestMethod "$base/v1/deals/$($deal.id)/step" -Method Post -Headers (Hdr $owner.accessToken) `
        -ContentType 'application/json; charset=utf-8' -Body (@{ status = $step } | ConvertTo-Json) | Out-Null
}

Write-Output "`n--- 3. Korotkaya zhaloba ne prinimaetsya ---"
try {
    Invoke-RestMethod "$base/v1/deals/$($deal.id)/dispute" -Method Post -Headers (Hdr $client.accessToken) `
        -ContentType 'application/json; charset=utf-8' -Body (@{ reason = 'плохо' } | ConvertTo-Json) | Out-Null
    Check $false 'po slovu "ploho" razobrat nechego'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 400) 'korotkaya zhaloba otklonena (400)'
}

Write-Output "`n--- 4. Spor otkryvaetsya ---"
$dispute = Invoke-RestMethod "$base/v1/deals/$($deal.id)/dispute" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json; charset=utf-8' `
    -Body (@{ reason = 'Договаривались на 40 метров траншеи, выкопано около 20' } | ConvertTo-Json)
Check ($dispute.status -eq 'open') "spor otkryt: $($dispute.status)"

$dealNow = Invoke-RestMethod "$base/v1/deals/$($deal.id)" -Headers (Bearer $client.accessToken)
Check ($dealNow.status -eq 'disputed') "sdelka v spore: $($dealNow.status)"

Write-Output "`n--- 5. Vtoroy spor po sdelke ne otkryt ---"
try {
    Invoke-RestMethod "$base/v1/deals/$($deal.id)/dispute" -Method Post -Headers (Hdr $owner.accessToken) `
        -ContentType 'application/json; charset=utf-8' `
        -Body (@{ reason = 'А заказчик не пускал меня на объект с утра' } | ConvertTo-Json) | Out-Null
    Check $false 'na sdelku odin otkrytyy spor'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 409) 'vtoroy spor otklonen (409)'
}

Write-Output "`n--- 6. Ochered moderacii ---"
$queue = Invoke-RestMethod "$base/v1/moderation/disputes" -Headers (Bearer $moder.accessToken)
$row = $queue.items | Where-Object { $_.id -eq $dispute.id }
Check ($null -ne $row) 'spor v ocheredi'
Check ($row.openedByClient -eq $true) 'vidno, kto pozhalovalsya'
Check ($row.reason -match 'траншеи') 'tekst zhaloby na meste'

try {
    Invoke-RestMethod "$base/v1/moderation/disputes" -Headers (Bearer $client.accessToken) | Out-Null
    Check $false 'ochered dostupna tolko moderacii'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 403) 'bez roli ochered zakryta (403)'
}

Write-Output "`n--- 7. Reshenie trebuet obosnovaniya ---"
try {
    Invoke-RestMethod "$base/v1/moderation/disputes/$($dispute.id)/resolve" -Method Post `
        -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
        -Body (@{ outcome = 'client'; resolution = 'ок' } | ConvertTo-Json) | Out-Null
    Check $false 'reshenie bez obosnovaniya ne prohodit'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 400) 'reshenie bez obosnovaniya otkloneno (400)'
}

Write-Output "`n--- 8. Reshenie v polzu zakazchika ---"
$resolved = Invoke-RestMethod "$base/v1/moderation/disputes/$($dispute.id)/resolve" -Method Post `
    -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
    -Body (@{
        outcome = 'client'
        resolution = 'По фотографиям видно около половины объёма. Оплата возвращается заказчику.'
    } | ConvertTo-Json)
Check ($resolved.status -eq 'resolved') "spor razobran: $($resolved.status)"
Check ($resolved.outcome -eq 'client') "ishod: $($resolved.outcome)"

$dealAfter = Invoke-RestMethod "$base/v1/deals/$($deal.id)" -Headers (Bearer $client.accessToken)
Check ($dealAfter.status -eq 'cancelled') "sdelka v polzu zakazchika otmenena: $($dealAfter.status)"

Write-Output "`n--- 9. Obe storony uznali o reshenii ---"
Start-Sleep -Milliseconds 700
$clientFeed = Invoke-RestMethod "$base/v1/notifications" -Headers (Bearer $client.accessToken)
$ownerFeed  = Invoke-RestMethod "$base/v1/notifications" -Headers (Bearer $owner.accessToken)
# Sravnivaem po marshrutu sobytiya, a ne po tekstu: PowerShell 5.1 chitaet
# otvet API v svoey kodirovke i lomaet kirillicu v sravnenii.
$dealRoute = "/deals/$($deal.id)"
Check (@($clientFeed.items | Where-Object { $_.data.route -eq $dealRoute }).Count -ge 1) 'zakazchik poluchil sobytiya po sdelke'
Check (@($ownerFeed.items  | Where-Object { $_.data.route -eq $dealRoute }).Count -ge 1) 'ispolnitel poluchil sobytiya po sdelke'

Write-Output "`n--- 10. Povtornoe reshenie nevozmozhno ---"
try {
    Invoke-RestMethod "$base/v1/moderation/disputes/$($dispute.id)/resolve" -Method Post `
        -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
        -Body (@{ outcome = 'owner'; resolution = 'Передумали: работа выполнена полностью.' } | ConvertTo-Json) | Out-Null
    Check $false 'razobrannyy spor ne peresmatrivaetsya'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 409) 'povtornoe reshenie otkloneno (409)'
}

Write-Output "`n--- 11. V baze ---"
$row = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT status, outcome FROM orders.disputes WHERE id='$($dispute.id)'"
Check ($row -match 'resolved\|client') "zapis v baze: $row"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: SPORY RABOTAYUT'; exit 0 }
