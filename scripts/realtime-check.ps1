# Skvoznaya proverka zhivyh sobytiy (ADR-6) na nastoyashchem stende:
# bilet na podklyuchenie -> stavka -> sobytie v kanale zadaniya.
#
# VNIMANIE: tolko latinitsa - PowerShell 5.1 chitaet .ps1 v ANSI.

$ErrorActionPreference = 'Continue'
$base = 'http://127.0.0.1:18080'
$centrifugo = 'http://127.0.0.1:18000'
$apiKey = 'traktor-local-centrifugo-api'
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

Write-Output "`n--- 1. Bilet na podklyuchenie ---"
$client = Login (NewPhone)
$owner  = Login (NewPhone)

$ticket = Invoke-RestMethod "$base/v1/realtime/token" -Headers (Bearer $client.accessToken)
Check ($ticket.token -match '^ey') 'bilet vydan'
Check ($null -ne $ticket.expiresAt) "srok deystviya: $($ticket.expiresAt)"

Write-Output "`n--- 2. Bez vhoda bileta net ---"
try {
    Invoke-RestMethod "$base/v1/realtime/token" | Out-Null
    Check $false 'bez vhoda bilet vydavat nelzya'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 401) 'bez vhoda otkaz (401)'
}

Write-Output "`n--- 3. Stavka popadaet v kanal zadaniya ---"
$cat = (Invoke-RestMethod "$base/v1/categories?kind=work").items | Select-Object -First 1
$draft = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{
        categoryId   = $cat.id
        title        = 'Auktsion dlya proverki zhivyh sobytiy'
        description  = 'Proveryaem, chto stavka srazu uhodit vsem uchastnikam torga.'
        geo          = @{ lat = 40.1872; lng = 44.5152 }
        address      = 'Erevan, Avan'
        budgetAmount = 120000
        mode         = 'auction'
        auction      = @{ durationH = 24; decisionWindowH = 12 }
    } | ConvertTo-Json)
$job = Invoke-RestMethod "$base/v1/jobs/$($draft.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
Check ($job.status -eq 'bidding') "torg idet: $($job.status)"

Invoke-RestMethod "$base/v1/jobs/$($job.id)/bids" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ price = 100000 } | ConvertTo-Json) | Out-Null
Start-Sleep -Milliseconds 700

# Istoriya kanala pokazyvaet, chto sobytie doshlo do Centrifugo.
$history = Invoke-RestMethod "$centrifugo/api/history" -Method Post `
    -Headers @{ 'X-API-Key' = $apiKey } -ContentType 'application/json' `
    -Body (@{ channel = "job:$($job.id)"; limit = 10 } | ConvertTo-Json)
$pubs = @($history.result.publications)
Check ($pubs.Count -ge 1) "sobytiy v kanale: $($pubs.Count)"
if ($pubs.Count -ge 1) {
    $last = $pubs[$pubs.Count - 1].data
    Check ($last.type -eq 'bid') "tip sobytiya: $($last.type)"
    Check ($last.price -eq 100000) "cena v sobytii: $($last.price)"
    Check ($null -ne $last.serverTime) "vremya servera est: $($last.serverTime)"
    Check ($null -eq $last.ownerId) 'lenta torga anonimna: imeni v sobytii net'
}

Write-Output "`n--- 4. Soobshchenie chata tozhe uhodit v kanal ---"
$fix = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{
        categoryId   = $cat.id
        title        = 'Zadanie dlya proverki chata'
        description  = 'Nuzhno dlya perepiski v proverke zhivyh sobytiy.'
        geo          = @{ lat = 40.1872; lng = 44.5152 }
        address      = 'Erevan, Avan'
        budgetAmount = 50000
        mode         = 'fixed'
    } | ConvertTo-Json)
$fixJob = Invoke-RestMethod "$base/v1/jobs/$($fix.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
$chat = Invoke-RestMethod "$base/v1/jobs/$($fixJob.id)/chat" -Method Post -Headers (Hdr $owner.accessToken)
Invoke-RestMethod "$base/v1/chats/$($chat.id)/messages" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{ text = 'Privet!' } | ConvertTo-Json) | Out-Null
Start-Sleep -Milliseconds 700

$chatHistory = Invoke-RestMethod "$centrifugo/api/history" -Method Post `
    -Headers @{ 'X-API-Key' = $apiKey } -ContentType 'application/json' `
    -Body (@{ channel = "chat:$($chat.id)"; limit = 10 } | ConvertTo-Json)
Check (@($chatHistory.result.publications).Count -ge 1) `
    "sobytiy v kanale chata: $(@($chatHistory.result.publications).Count)"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: ZHIVYE SOBYTIYA RABOTAYUT'; exit 0 }
