# Skvoznaya proverka chata (TZ 2.12) na nastoyashchey baze:
# ispolnitel pishet po zadaniyu -> kontakty maskiruyutsya -> zakazchik chitaet ->
# neprochitannye obnulyayutsya -> posle podtverzhdeniya sdelki kontakty ne pryachutsya.
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
function NewPhone { '+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999) }

Write-Output "`n--- 1. Zadanie i dva uchastnika ---"
$client = Login (NewPhone)
$owner  = Login (NewPhone)
$other  = Login (NewPhone)

# Zakazchiku dadim imya - ono dolzhno poyavitsya v spiske chatov ispolnitelya.
Invoke-RestMethod "$base/v1/me" -Method Patch -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{ name = 'Tigran' } | ConvertTo-Json) | Out-Null

$cat = (Invoke-RestMethod "$base/v1/categories?kind=work").items | Select-Object -First 1
$draft = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{
        categoryId   = $cat.id
        title        = 'Ubrat sneg s parkovki'
        description  = 'Parkovka na 20 mest, sneg ubrat i vyvezti do utra ponedelnika.'
        geo          = @{ lat = 40.1872; lng = 44.5152 }
        address      = 'Erevan, Ajapnyak'
        budgetAmount = 60000
        mode         = 'fixed'
    } | ConvertTo-Json)
$job = Invoke-RestMethod "$base/v1/jobs/$($draft.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
Check ($job.status -eq 'collecting_offers') 'zadanie opublikovano'

Write-Output "`n--- 2. Ispolnitel otkryvaet perepisku ---"
$chat = Invoke-RestMethod "$base/v1/jobs/$($job.id)/chat" -Method Post -Headers (Hdr $owner.accessToken)
Check ($null -ne $chat.id -and $chat.kind -eq 'pre_deal') "chat otkryt: $($chat.kind)"

$again = Invoke-RestMethod "$base/v1/jobs/$($job.id)/chat" -Method Post -Headers (Hdr $owner.accessToken)
Check ($again.id -eq $chat.id) 'povtornoe otkrytie ne sozdaet vtoruyu vetku'

Write-Output "`n--- 3. Kontakty maskiruyutsya do sdelki ---"
$sent = Invoke-RestMethod "$base/v1/chats/$($chat.id)/messages" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ text = 'Dobryy den! Zvonite +374 91 234 567' } | ConvertTo-Json)
Check ($sent.contactsMasked -eq $true) 'otpravitel preduprezhden o skrytii kontakta'
Check ($sent.message.text -notmatch '234') "telefon ne ushel sobesedniku: $($sent.message.text)"

$normal = Invoke-RestMethod "$base/v1/chats/$($chat.id)/messages" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ text = 'Ploshchad 20 mest, uberu za 3 chasa' } | ConvertTo-Json)
Check ($normal.contactsMasked -eq $false) 'obychnye chisla ne schitayutsya kontaktami'

Write-Output "`n--- 4. Spisok chatov zakazchika ---"
$chats = Invoke-RestMethod "$base/v1/chats" -Headers @{ Authorization = "Bearer $($client.accessToken)" }
$row = $chats.items | Select-Object -First 1
Check (@($chats.items).Count -eq 1) "chatov u zakazchika: $(@($chats.items).Count)"
Check ($row.unread -eq 2) "neprochitannyh: $($row.unread)"
Check ($row.jobTitle -eq 'Ubrat sneg s parkovki') 'v spiske vidno nazvanie zadaniya'

Write-Output "`n--- 5. Chuzhaya perepiska zakryta ---"
try {
    Invoke-RestMethod "$base/v1/chats/$($chat.id)/messages" -Headers @{ Authorization = "Bearer $($other.accessToken)" } | Out-Null
    Check $false 'postoronniy ne dolzhen chitat perepisku'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 403) 'chuzhaya perepiska zakryta (403)'
}

Write-Output "`n--- 6. Otkryl chat - znachit prochital ---"
Invoke-RestMethod "$base/v1/chats/$($chat.id)/messages" -Headers @{ Authorization = "Bearer $($client.accessToken)" } | Out-Null
$after = Invoke-RestMethod "$base/v1/chats" -Headers @{ Authorization = "Bearer $($client.accessToken)" }
Check ((@($after.items) | Select-Object -First 1).unread -eq 0) 'neprochitannye obnulilis'

Write-Output "`n--- 7. Posle sdelki kontakty ne pryachutsya ---"
$offer = Invoke-RestMethod "$base/v1/jobs/$($job.id)/offers" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ kind = 'accept'; price = 60000 } | ConvertTo-Json)
Invoke-RestMethod "$base/v1/offers/$($offer.id)/accept" -Method Post -Headers (Hdr $client.accessToken) | Out-Null
Invoke-RestMethod "$base/v1/jobs/$($job.id)/deal" -Method Post -Headers (Hdr $client.accessToken) | Out-Null

$dealChat = Invoke-RestMethod "$base/v1/jobs/$($job.id)/chat" -Method Post -Headers (Hdr $owner.accessToken)
Check ($dealChat.kind -eq 'deal') "chat stal chatom sdelki: $($dealChat.kind)"

$open = Invoke-RestMethod "$base/v1/chats/$($chat.id)/messages" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ text = 'Naberu s +374 91 234 567' } | ConvertTo-Json)
Check ($open.contactsMasked -eq $false) 'v sdelke telefon ne pryachetsya'

Write-Output "`n--- 8. V baze ---"
$row = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT count(*) FROM orders.messages WHERE chat_id='$($chat.id)'"
Check ([int]$row -eq 3) "soobshcheniy v baze: $row"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: CHAT RABOTAET'; exit 0 }
