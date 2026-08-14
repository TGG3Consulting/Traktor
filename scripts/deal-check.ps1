# Skvoznaya proverka sdelki (TZ 2.11) na nastoyashchey baze:
# vybor ispolnitelya -> podtverzhdenie -> vyehal -> nachal -> zavershil ->
# priemka zakazchikom. Plus proverka prav: kto kakoy shag delaet.
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
function Step($token, $dealId, $status) {
    return Invoke-RestMethod "$base/v1/deals/$dealId/step" -Method Post -Headers (Hdr $token) `
        -ContentType 'application/json' -Body (@{ status = $status } | ConvertTo-Json)
}

Write-Output "`n--- 1. Zadanie, otklik, vybor ---"
$client = Login ('+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999))
$owner  = Login ('+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999))
$other  = Login ('+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999))

$cat = (Invoke-RestMethod "$base/v1/categories?kind=work").items | Select-Object -First 1
$draft = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{
        categoryId   = $cat.id
        title        = 'Planirovka uchastka buldozerom'
        description  = 'Uchastok 12 sotok, nuzhna planirovka pod fundament i vyvoz lishnego grunta.'
        geo          = @{ lat = 40.1872; lng = 44.5152 }
        address      = 'Erevan, Davtashen'
        budgetAmount = 90000
        mode         = 'fixed'
    } | ConvertTo-Json)
Invoke-RestMethod "$base/v1/jobs/$($draft.id)/publish" -Method Post -Headers (Hdr $client.accessToken) | Out-Null
$offer = Invoke-RestMethod "$base/v1/jobs/$($draft.id)/offers" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ kind = 'accept'; price = 90000; eta = 'zavtra' } | ConvertTo-Json)
Invoke-RestMethod "$base/v1/offers/$($offer.id)/accept" -Method Post -Headers (Hdr $client.accessToken) | Out-Null
Check $true 'ispolnitel vybran'

Write-Output "`n--- 2. Podtverzhdenie sdelki ---"
$deal = Invoke-RestMethod "$base/v1/jobs/$($draft.id)/deal" -Method Post -Headers (Hdr $client.accessToken)
Check ($deal.status -eq 'confirmed' -and $deal.price -eq 90000) "sdelka sozdana: $($deal.status), tsena $($deal.price)"
Check ($deal.timeline.Count -eq 1) 'v taymlayne pervaya otmetka'

$again = Invoke-RestMethod "$base/v1/jobs/$($draft.id)/deal" -Method Post -Headers (Hdr $client.accessToken)
Check ($again.id -eq $deal.id) 'povtornoe podtverzhdenie ne sozdaet vtoruyu sdelku'

Write-Output "`n--- 3. Prava na shagi ---"
try {
    Step $client.accessToken $deal.id 'on_the_way' | Out-Null
    Check $false 'zakazchik ne dolzhen "vyezzhat" za ispolnitelya'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 409) 'shag ispolnitelya nedostupen zakazchiku (409)'
}
try {
    Step $client.accessToken $deal.id 'completed' | Out-Null
    Check $false 'nelzya prinyat rabotu, kotoraya ne nachinalas'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 409) 'pereprygnut shagi nelzya (409)'
}
try {
    Invoke-RestMethod "$base/v1/deals/$($deal.id)" -Headers @{ Authorization = "Bearer $($other.accessToken)" } | Out-Null
    Check $false 'postoronniy ne dolzhen videt sdelku'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 403) 'postoronniy sdelku ne vidit (403)'
}

Write-Output "`n--- 4. Rabota ---"
$s1 = Step $owner.accessToken $deal.id 'on_the_way'
Check ($s1.status -eq 'on_the_way') 'ispolnitel vyehal'
$s2 = Step $owner.accessToken $deal.id 'in_progress'
Check ($s2.status -eq 'in_progress') 'rabota nachata'
$s3 = Step $owner.accessToken $deal.id 'work_done'
Check ($s3.status -eq 'work_done') 'rabota zavershena'
Check ($null -ne $s3.acceptanceDeadline) "srok priemki naznachen: $($s3.acceptanceDeadline)"

$jobNow = Invoke-RestMethod "$base/v1/jobs/$($draft.id)" -Headers @{ Authorization = "Bearer $($client.accessToken)" }
Check ($jobNow.status -eq 'work_done') "status zadaniya idet sledom: $($jobNow.status)"

Write-Output "`n--- 5. Priemka ---"
$done = Step $client.accessToken $deal.id 'completed'
Check ($done.status -eq 'completed' -and $null -ne $done.closedAt) 'zakazchik prinyal rabotu'
Check ($done.timeline.Count -eq 5) "taymlayn pomnit vse shagi: $($done.timeline.Count)"

$final = Invoke-RestMethod "$base/v1/jobs/$($draft.id)" -Headers @{ Authorization = "Bearer $($client.accessToken)" }
Check ($final.status -eq 'completed') "zadanie zaversheno: $($final.status)"

Write-Output "`n--- 6. Sdelka vidna obeim storonam ---"
$mineClient = Invoke-RestMethod "$base/v1/deals/my" -Headers @{ Authorization = "Bearer $($client.accessToken)" }
$mineOwner  = Invoke-RestMethod "$base/v1/deals/my" -Headers @{ Authorization = "Bearer $($owner.accessToken)" }
Check (@($mineClient.items).Count -ge 1 -and @($mineOwner.items).Count -ge 1) 'sdelka est u oboih'

Write-Output "`n--- 7. V baze ---"
$row = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT status || '|' || jsonb_array_length(timeline) FROM orders.deals WHERE job_id='$($draft.id)'"
Check ($row -match 'completed\|5') "v baze: $row"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: SDELKA RABOTAET'; exit 0 }
