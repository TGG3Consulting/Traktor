# Skvoznaya proverka nastroek uvedomleniy (TZ 2.14) na nastoyashchey baze:
# umolchaniya -> vyklyuchennaya gruppa -> sohranenie -> sobytie vse ravno v lente.
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

Write-Output "`n--- 1. Umolchaniya ---"
$client = Login (NewPhone)
$owner  = Login (NewPhone)

$p = Invoke-RestMethod "$base/v1/notifications/settings" -Headers (Bearer $client.accessToken)
Check ($p.deals -eq $true)      "sdelki vklyucheny: $($p.deals)"
Check ($p.chat -eq $true)       "chat vklyuchen: $($p.chat)"
Check ($p.marketing -eq $false) "marketing vyklyuchen (opt-in): $($p.marketing)"
Check ($p.quietHours -eq $true) "tihie chasy vklyucheny: $($p.quietHours)"
Check ($p.quietFrom -eq 22 -and $p.quietTo -eq 8) "tishina $($p.quietFrom):00-$($p.quietTo):00"

Write-Output "`n--- 2. Vyklyuchaem gruppu ---"
$p = Invoke-RestMethod "$base/v1/notifications/settings" -Method Put -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{ deals = $false } | ConvertTo-Json)
Check ($p.deals -eq $false) "sdelki vyklyucheny: $($p.deals)"
Check ($p.chat -eq $true)   'ostalnye gruppy ne tronuty'

$again = Invoke-RestMethod "$base/v1/notifications/settings" -Headers (Bearer $client.accessToken)
Check ($again.deals -eq $false) 'nastroyka perezhila povtornyy zapros'

Write-Output "`n--- 3. Sobytie vse ravno popadaet v centr uvedomleniy ---"
$cat = (Invoke-RestMethod "$base/v1/categories?kind=work").items | Select-Object -First 1
$draft = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{
        categoryId   = $cat.id
        title        = 'Proverka nastroek uvedomleniy'
        description  = 'Zadanie dlya proverki togo, chto sobytie popadaet v lentu.'
        geo          = @{ lat = 40.1872; lng = 44.5152 }
        address      = 'Erevan, Avan'
        budgetAmount = 40000
        mode         = 'fixed'
    } | ConvertTo-Json)
$job = Invoke-RestMethod "$base/v1/jobs/$($draft.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
Invoke-RestMethod "$base/v1/jobs/$($job.id)/offers" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ kind = 'accept'; price = 40000 } | ConvertTo-Json) | Out-Null
Start-Sleep -Milliseconds 500

$feed = Invoke-RestMethod "$base/v1/notifications" -Headers (Bearer $client.accessToken)
Check (@($feed.items).Count -ge 1) "sobytie v lente est: $(@($feed.items).Count)"
Check ($feed.unread -ge 1) "neprochitannoe est: $($feed.unread)"

Write-Output "`n--- 4. Chasy tishiny mozhno vyklyuchit ---"
$p = Invoke-RestMethod "$base/v1/notifications/settings" -Method Put -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{ quietHours = $false; outbidAlways = $true } | ConvertTo-Json)
Check ($p.quietHours -eq $false)  'tihie chasy vyklyucheny'
Check ($p.outbidAlways -eq $true) 'razreshili budit iz-za perebitoy stavki'

Write-Output "`n--- 5. V baze ---"
$row = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT deals, quiet_hours FROM notifications.prefs WHERE user_id='$($client.user.id)'"
Check ($row -match 'f\|f') "nastroyki sohraneny v baze: $row"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: NASTROYKI RABOTAYUT'; exit 0 }
