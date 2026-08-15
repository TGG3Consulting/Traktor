# Skvoznaya proverka prevyu ssylok v messendzherah (TZ 4.2) na zhivom stende:
# bot vidit og-tegi s nazvaniem i cenoy, chelovek poluchaet prilozhenie.
#
# Fayl v UTF-8 s BOM: v nem est russkiy tekst zadaniya.

$ErrorActionPreference = 'Continue'
$api = 'http://127.0.0.1:18080'
$web = 'http://127.0.0.1:18090'
$failed = $false
function Check($cond, $msg) {
    if ($cond) { Write-Output "  OK: $msg" } else { Write-Output "  PROVAL: $msg"; $script:failed = $true }
}
function Login($phone) {
    Invoke-RestMethod "$api/v1/auth/otp/start" -Method Post -ContentType 'application/json; charset=utf-8' `
        -Body (@{ phone = $phone } | ConvertTo-Json) | Out-Null
    return Invoke-RestMethod "$api/v1/auth/otp/verify" -Method Post -ContentType 'application/json; charset=utf-8' `
        -Headers @{ 'Idempotency-Key' = [guid]::NewGuid().ToString() } `
        -Body (@{ phone = $phone; code = '000000' } | ConvertTo-Json)
}
function Hdr($t) { @{ Authorization = "Bearer $t"; 'Idempotency-Key' = [guid]::NewGuid().ToString() } }
function NewPhone { '+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999) }
function Get-Page($url, $agent) {
    return (Invoke-WebRequest -Uri $url -Headers @{ 'User-Agent' = $agent } -UseBasicParsing).Content
}

$client = Login (NewPhone)

Write-Output "`n--- 1. Gotovim zadanie so vsemi dannymi ---"
$cat = (Invoke-RestMethod "$api/v1/categories?kind=work").items | Select-Object -First 1
$d = Invoke-RestMethod "$api/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{
        categoryId = $cat.id
        title = 'Экскаватор на день, Аван'
        description = 'Выкопать траншею 40 метров под водопровод, грунт мягкий, подъезд есть.'
        geo = @{ lat = 40.1872; lng = 44.5152 }
        address = 'Ереван, Аван'
        budgetAmount = 120000
        mode = 'fixed'
    } | ConvertTo-Json)
$job = Invoke-RestMethod "$api/v1/jobs/$($d.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
Check ($job.status -ne 'draft') "zadanie opublikovano: $($job.status)"

Write-Output "`n--- 2. Bot messendzhera vidit kartochku ---"
$bot = Get-Page "$web/jobs/$($job.id)" 'WhatsApp/2.23.20.0'
Check ($bot -match 'og:title') 'est og-tegi'
Check ($bot -match 'og:image') 'est kartinka dlya prevyu'
Check ($bot -match '120') 'cena v opisanii'
Check ($bot -match "app.homly.am/jobs/$($job.id)") 'ssylka vedet v prilozhenie'

Write-Output "`n--- 3. Telegram i Facebook tozhe ---"
foreach ($agent in @('TelegramBot (like TwitterBot)', 'facebookexternalhit/1.1')) {
    $page = Get-Page "$web/jobs/$($job.id)" $agent
    Check ($page -match 'og:title') "prevyu dlya $agent"
}

Write-Output "`n--- 4. Chelovek poluchaet prilozhenie, a ne zaglushku ---"
$human = Get-Page "$web/jobs/$($job.id)" 'Mozilla/5.0 (Windows NT 10.0; Win64) Chrome/124.0'
Check ($human -match 'flutter_bootstrap') 'brauzeru otdaetsya prilozhenie'
Check (-not ($human -match 'og:site_name')) 'zaglushka cheloveku ne pokazyvaetsya'

Write-Output "`n--- 5. Prevyu profilya ---"
Invoke-RestMethod "$api/v1/me" -Method Patch -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json; charset=utf-8' `
    -Body (@{ name = 'Ашот Саркисян'; city = 'Ереван' } | ConvertTo-Json) | Out-Null
$profile = Get-Page "$web/users/$($client.user.id)" 'WhatsApp/2.23.20.0'
Check ($profile -match 'og:title') 'u profilya est prevyu'
Check ($profile -match "app.homly.am/users/$($client.user.id)") 'ssylka vedet v kartochku'

Write-Output "`n--- 6. Bitaya ssylka ne lomaet prevyu ---"
$broken = Get-Page "$web/jobs/00000000-0000-0000-0000-000000000000" 'WhatsApp/2.23.20.0'
Check ($broken -match 'og:title') 'otdaetsya stranica, a ne oshibka'

Write-Output "`n--- 7. Kartinka po umolchaniyu na meste ---"
$img = Invoke-WebRequest -Uri "$web/icons/og-default.png" -UseBasicParsing
Check ($img.StatusCode -eq 200) "og-default.png otdaetsya: $($img.StatusCode)"
Check ($img.Content.Length -gt 5000) "razmer kartinki: $($img.Content.Length) bayt"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: PREVYU SSYLOK RABOTAET'; exit 0 }
