# Skvoznaya proverka upravleniya polzovatelyami (TZ 4.1, p.3 i 8) na nastoyashchey baze:
# poisk -> zamorozka -> zapret otklikov -> ban -> obryv sessiy -> snyatie -> zhurnal.
#
# Fayl v UTF-8 s BOM: v nem est russkiy tekst prichin.

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

$moder = Login '+37490000001'
$clientPhone = NewPhone
$ownerPhone  = NewPhone
$client = Login $clientPhone
$owner  = Login $ownerPhone

Write-Output "`n--- 1. Poisk po nomeru ---"
$found = Invoke-RestMethod "$base/v1/moderation/users?q=$([uri]::EscapeDataString($ownerPhone))" `
    -Headers (Bearer $moder.accessToken)
$row = $found.items | Where-Object { $_.id -eq $owner.user.id }
Check ($null -ne $row) 'chelovek nayden po nomeru'
Check ($row.status -eq 'active') "sostoyanie po umolchaniyu: $($row.status)"

try {
    Invoke-RestMethod "$base/v1/moderation/users?q=$([uri]::EscapeDataString($ownerPhone))" `
        -Headers (Bearer $client.accessToken) | Out-Null
    Check $false 'razdel dostupen tolko moderacii'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 403) 'bez roli razdel zakryt (403)'
}

Write-Output "`n--- 2. Reshenie bez prichiny ne prohodit ---"
try {
    Invoke-RestMethod "$base/v1/moderation/users/$($owner.user.id)/status" -Method Post `
        -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
        -Body (@{ status = 'frozen'; reason = 'плохой' } | ConvertTo-Json) | Out-Null
    Check $false 'prichina obyazatelna'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 400) 'korotkaya prichina otklonena (400)'
}

Write-Output "`n--- 3. Zamorozka ---"
$frozen = Invoke-RestMethod "$base/v1/moderation/users/$($owner.user.id)/status" -Method Post `
    -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
    -Body (@{ status = 'frozen'; reason = 'Просит оплату мимо площадки в переписке' } | ConvertTo-Json)
Check ($frozen.status -eq 'frozen') "sostoyanie: $($frozen.status)"

Write-Output "`n--- 4. Zamorozhennyy ne mozhet otkliknutsya ---"
# Novyy token: sostoyanie edet v tokene, staryy vypushchen do zamorozki.
$owner = Login $ownerPhone
$cat = (Invoke-RestMethod "$base/v1/categories?kind=work").items | Select-Object -First 1
$d = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{
        categoryId = $cat.id
        title = 'Planirovka uchastka dlya proverki zamorozki'
        description = 'Zadanie, na kotorom proveryaem zapret otklikov posle zamorozki.'
        geo = @{ lat = 40.1872; lng = 44.5152 }
        address = 'Erevan, Nor Nork'
        budgetAmount = 60000
        mode = 'fixed'
    } | ConvertTo-Json)
$job = Invoke-RestMethod "$base/v1/jobs/$($d.id)/publish" -Method Post -Headers (Hdr $client.accessToken)

try {
    Invoke-RestMethod "$base/v1/jobs/$($job.id)/offers" -Method Post -Headers (Hdr $owner.accessToken) `
        -ContentType 'application/json; charset=utf-8' `
        -Body (@{ kind = 'accept'; price = 60000 } | ConvertTo-Json) | Out-Null
    Check $false 'zamorozka zapreshchaet otkliki'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 403) 'otklik zamorozhennogo otklonen (403)'
}

Write-Output "`n--- 5. Vhod i chtenie ostayutsya ---"
$feed = Invoke-RestMethod "$base/v1/jobs?sort=new&limit=5" -Headers (Bearer $owner.accessToken)
Check ($null -ne $feed.items) 'zamorozhennyy vidit lentu: u nego mogut byt nezakrytye sdelki'

Write-Output "`n--- 6. Ban ---"
$banned = Invoke-RestMethod "$base/v1/moderation/users/$($owner.user.id)/status" -Method Post `
    -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
    -Body (@{ status = 'banned'; reason = 'Нарушения продолжились после заморозки' } | ConvertTo-Json)
Check ($banned.status -eq 'banned') "sostoyanie: $($banned.status)"

try {
    Invoke-RestMethod "$base/v1/auth/otp/start" -Method Post -ContentType 'application/json; charset=utf-8' `
        -Body (@{ phone = $ownerPhone } | ConvertTo-Json) | Out-Null
    Invoke-RestMethod "$base/v1/auth/otp/verify" -Method Post -ContentType 'application/json; charset=utf-8' `
        -Headers @{ 'Idempotency-Key' = [guid]::NewGuid().ToString() } `
        -Body (@{ phone = $ownerPhone; code = '000000' } | ConvertTo-Json) | Out-Null
    Check $false 'zabanennomu vhod zakryt'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 403) 'vhod zabanennogo otklonen (403)'
}

Write-Output "`n--- 7. Starye sessii oborvany ---"
try {
    Invoke-RestMethod "$base/v1/auth/refresh" -Method Post -ContentType 'application/json; charset=utf-8' `
        -Body (@{ refreshToken = $owner.refreshToken } | ConvertTo-Json) | Out-Null
    Check $false 'ban dolzhen rabotat srazu, a ne cherez 30 dney'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -in 401, 403) 'prodlenie sessii otkloneno'
}

Write-Output "`n--- 8. Ban obratim ---"
Invoke-RestMethod "$base/v1/moderation/users/$($owner.user.id)/status" -Method Post `
    -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
    -Body (@{ status = 'active'; reason = 'Разобрались: жалоба была на другого человека' } | ConvertTo-Json) | Out-Null
$back = Login $ownerPhone
Check ($null -ne $back.accessToken) 'posle snyatiya ogranicheniy vhod rabotaet'

$offer = Invoke-RestMethod "$base/v1/jobs/$($job.id)/offers" -Method Post -Headers (Hdr $back.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{ kind = 'accept'; price = 60000 } | ConvertTo-Json)
Check ($null -ne $offer.id) 'otkliki snova rabotayut'

Write-Output "`n--- 9. Zhurnal resheniy ---"
$card = Invoke-RestMethod "$base/v1/moderation/users/$($owner.user.id)" -Headers (Bearer $moder.accessToken)
Check (@($card.history).Count -ge 3) "v zhurnale vse resheniya: $(@($card.history).Count)"
Check ($card.history[0].action -eq 'status:active') "svezhee sverhu: $($card.history[0].action)"
Check ($card.phone -eq $ownerPhone) 'moderator vidit nomer dlya svyazi'

Write-Output "`n--- 10. Na sebya reshenie ne primenit ---"
try {
    Invoke-RestMethod "$base/v1/moderation/users/$($moder.user.id)/status" -Method Post `
        -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
        -Body (@{ status = 'banned'; reason = 'Проверка защиты от самоблокировки' } | ConvertTo-Json) | Out-Null
    Check $false 'moderator ne banit sebya'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 400) 'samoblokirovka otklonena (400)'
}

Write-Output "`n--- 11. V baze ---"
$row = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT COUNT(*) FROM identity.admin_actions WHERE target_id='$($owner.user.id)'"
Check ([int]$row -ge 3) "zapisey v zhurnale: $row"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: MODERACIYA POLZOVATELEY RABOTAET'; exit 0 }
