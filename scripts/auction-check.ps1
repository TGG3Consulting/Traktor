# Skvoznaya proverka auktsiona (TZ 2.9) na nastoyashchey baze:
# publikatsiya -> stavki dvuh ispolniteley -> zapret stavki vyshe luchshey ->
# finish -> okno resheniya -> vybor pobeditelya -> podtverzhdenie sdelki.
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
function NewPhone { '+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999) }

Write-Output "`n--- 1. Auktsion so startovoy tsenoy 120 000 ---"
$client = Login (NewPhone)
$ownerA = Login (NewPhone)
$ownerB = Login (NewPhone)

$cat = (Invoke-RestMethod "$base/v1/categories?kind=work").items | Select-Object -First 1
$draft = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{
        categoryId   = $cat.id
        title        = 'Vykopat kotlovan pod fundament'
        description  = 'Kotlovan 8 na 10 metrov, glubina 2 m, grunt srednyy, podezd svobodnyy.'
        geo          = @{ lat = 40.1872; lng = 44.5152 }
        address      = 'Erevan, Nork'
        budgetAmount = 120000
        mode         = 'auction'
        auction      = @{ durationH = 24; decisionWindowH = 12 }
    } | ConvertTo-Json)
$job = Invoke-RestMethod "$base/v1/jobs/$($draft.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
Check ($job.status -eq 'bidding') "torg idet: $($job.status)"
Check ($null -ne $job.auction.endsAt) 'vremya finisha poschitano serverom'

Write-Output "`n--- 2. Stavki ---"
$bidA = Invoke-RestMethod "$base/v1/jobs/$($job.id)/bids" -Method Post -Headers (Hdr $ownerA.accessToken) `
    -ContentType 'application/json' -Body (@{ price = 100000; comment = 'Ekskavator JCB' } | ConvertTo-Json)
Check ($bidA.status -eq 'active') "pervaya stavka: $($bidA.price)"

try {
    Invoke-RestMethod "$base/v1/jobs/$($job.id)/bids" -Method Post -Headers (Hdr $ownerB.accessToken) `
        -ContentType 'application/json' -Body (@{ price = 110000 } | ConvertTo-Json) | Out-Null
    Check $false 'stavka vyshe luchshey dolzhna otklonyatsya'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 422) 'stavka vyshe luchshey otklonena (422)'
}

try {
    Invoke-RestMethod "$base/v1/jobs/$($job.id)/bids" -Method Post -Headers (Hdr $ownerB.accessToken) `
        -ContentType 'application/json' -Body (@{ price = 20000 } | ConvertTo-Json) | Out-Null
    Check $false 'demping dolzhen otsekatsya'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 422) 'slishkom nizkaya stavka otklonena (422)'
}

$bidB = Invoke-RestMethod "$base/v1/jobs/$($job.id)/bids" -Method Post -Headers (Hdr $ownerB.accessToken) `
    -ContentType 'application/json' -Body (@{ price = 90000 } | ConvertTo-Json)
Check ($bidB.price -eq 90000) 'vtoraya stavka nizhe pervoy'

try {
    Invoke-RestMethod "$base/v1/jobs/$($job.id)/bids" -Method Post -Headers (Hdr $client.accessToken) `
        -ContentType 'application/json' -Body (@{ price = 80000 } | ConvertTo-Json) | Out-Null
    Check $false 'zakazchik ne dolzhen stavit na svoe zadanie'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 403) 'zakazchiku stavit zapreshcheno (403)'
}

Write-Output "`n--- 3. Lenta torga anonimna ---"
$bids = Invoke-RestMethod "$base/v1/jobs/$($job.id)/bids" -Headers @{ Authorization = "Bearer $($ownerA.accessToken)" }
$firstRow = $bids.items | Select-Object -First 1
Check (@($bids.items).Count -ge 2) "v lente stavok: $(@($bids.items).Count)"
Check ($null -eq $firstRow.ownerId) 'imena uchastnikov ne raskryvayutsya'
Check ($firstRow.rank -eq 1 -and $firstRow.price -eq 90000) 'luchshaya stavka pervaya v lente'
$mineRow = $bids.items | Where-Object { $_.mine -eq $true } | Select-Object -First 1
Check ($null -ne $mineRow) 'svoyu stavku ispolnitel uznaet po priznaku mine'

Write-Output "`n--- 4. Finish i okno resheniya ---"
$finished = Invoke-RestMethod "$base/v1/jobs/$($job.id)/auction/finish" -Method Post -Headers (Hdr $client.accessToken)
Check ($finished.status -eq 'deciding') "posle finisha: $($finished.status)"
Check ($finished.winnerBidId -eq $bidB.id) 'pobeditel - samaya nizkaya stavka'
Check ($null -ne $finished.decisionDeadline) "okno resheniya do: $($finished.decisionDeadline)"

Write-Output "`n--- 5. Vybor pobeditelya ---"
$won = Invoke-RestMethod "$base/v1/bids/$($bidB.id)/accept" -Method Post -Headers (Hdr $client.accessToken)
Check ($won.status -eq 'won') 'stavka pomechena kak vyigravshaya'

$after = Invoke-RestMethod "$base/v1/jobs/$($job.id)" -Headers @{ Authorization = "Bearer $($client.accessToken)" }
Check ($after.status -eq 'deal_pending') "zadanie zhdet podtverzhdeniya: $($after.status)"

$bidsAfter = Invoke-RestMethod "$base/v1/jobs/$($job.id)/bids" -Headers @{ Authorization = "Bearer $($ownerA.accessToken)" }
$lost = $bidsAfter.items | Where-Object { $_.id -eq $bidA.id } | Select-Object -First 1
Check ($lost.status -eq 'lost') "proigravshaya stavka zakryta: $($lost.status)"

Write-Output "`n--- 6. Sdelka posle auktsiona ---"
$deal = Invoke-RestMethod "$base/v1/jobs/$($job.id)/deal" -Method Post -Headers (Hdr $client.accessToken)
Check ($deal.price -eq 90000) "tsena sdelki - tsena pobedivshey stavki: $($deal.price)"

Write-Output "`n--- 7. V baze ---"
$row = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT count(*) FROM orders.bids WHERE job_id='$($job.id)'"
Check ([int]$row -eq 2) "stavok v baze: $row"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: AUKTSION RABOTAET'; exit 0 }
