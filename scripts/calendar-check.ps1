# Skvoznaya proverka kalendarya zanyatosti (TZ 3.1) na nastoyashchey baze:
# den so sdelkoy -> svoya otmetka "ne rabotayu" -> snyatie -> chuzhaya zanyatost.
#
# Fayl v UTF-8 s BOM: v nem est russkie pometki dney.

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

$month = (Get-Date).ToString('yyyy-MM')
$day   = (Get-Date).AddDays(3).ToString('yyyy-MM-dd')

Write-Output "`n--- 1. Pustoy kalendar ---"
$client = Login (NewPhone)
$owner  = Login (NewPhone)
$other  = Login (NewPhone)

$cal = Invoke-RestMethod "$base/v1/crm/calendar?month=$month" -Headers (Bearer $owner.accessToken)
Check (@($cal.items).Count -eq 0) "u novogo ispolnitelya zanyatosti net: $(@($cal.items).Count)"

Write-Output "`n--- 2. Svoya otmetka 'ne rabotayu' ---"
Invoke-RestMethod "$base/v1/crm/calendar" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json; charset=utf-8' `
    -Body (@{ day = $day; note = 'ремонт техники' } | ConvertTo-Json) | Out-Null

$cal = Invoke-RestMethod "$base/v1/crm/calendar?month=$month" -Headers (Bearer $owner.accessToken)
$mine = $cal.items | Where-Object { $_.day -eq $day }
Check ($null -ne $mine) "den otmechen: $day"
Check ($mine.source -eq 'manual') "istochnik otmetki: $($mine.source)"
Check ($mine.note -match 'ремонт') "pometka sohranena: $($mine.note)"

Write-Output "`n--- 3. Chuzhaya zanyatost ne vidna ---"
$foreign = Invoke-RestMethod "$base/v1/crm/calendar?month=$month" -Headers (Bearer $other.accessToken)
Check (@($foreign.items | Where-Object { $_.day -eq $day }).Count -eq 0) 'chuzhoy kalendar pustoy'

Write-Output "`n--- 4. Otmetku mozhno snyat ---"
Invoke-RestMethod "$base/v1/crm/calendar/$day" -Method Delete -Headers (Hdr $owner.accessToken) | Out-Null
$cal = Invoke-RestMethod "$base/v1/crm/calendar?month=$month" -Headers (Bearer $owner.accessToken)
Check (@($cal.items | Where-Object { $_.day -eq $day }).Count -eq 0) 'posle snyatiya den svoboden'

Write-Output "`n--- 5. Den so sdelkoy zanyat sam ---"
$cat = (Invoke-RestMethod "$base/v1/categories?kind=work").items | Select-Object -First 1
$workDay = (Get-Date).AddDays(5).ToString('yyyy-MM-dd')
$d = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{
        categoryId = $cat.id
        title = 'Rabota dlya kalendarya'
        description = 'Zadanie s tochnoy datoy, chtoby den popal v kalendar ispolnitelya.'
        geo = @{ lat = 40.1872; lng = 44.5152 }
        address = 'Erevan, Avan'
        budgetAmount = 70000
        mode = 'fixed'
        dateMode = 'exact'
        dateStart = "$workDay" + 'T09:00:00Z'
    } | ConvertTo-Json)
$job = Invoke-RestMethod "$base/v1/jobs/$($d.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
$offer = Invoke-RestMethod "$base/v1/jobs/$($job.id)/offers" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{ kind = 'accept'; price = 70000 } | ConvertTo-Json)
Invoke-RestMethod "$base/v1/offers/$($offer.id)/accept" -Method Post -Headers (Hdr $client.accessToken) | Out-Null
$deal = Invoke-RestMethod "$base/v1/jobs/$($job.id)/deal" -Method Post -Headers (Hdr $client.accessToken)

$cal = Invoke-RestMethod "$base/v1/crm/calendar?month=$month" -Headers (Bearer $owner.accessToken)
$busy = $cal.items | Where-Object { $_.day -eq $workDay }
Check ($null -ne $busy) "den raboty zanyat: $workDay"
Check ($busy.source -eq 'deal') "istochnik: $($busy.source)"
Check ($busy.dealId -eq $deal.id) 'iz kalendarya otkryvaetsya sdelka'

Write-Output "`n--- 6. Sdelka silnee svoey otmetki ---"
Invoke-RestMethod "$base/v1/crm/calendar" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json; charset=utf-8' `
    -Body (@{ day = $workDay; note = 'peredumal' } | ConvertTo-Json) | Out-Null
$cal = Invoke-RestMethod "$base/v1/crm/calendar?month=$month" -Headers (Bearer $owner.accessToken)
$same = @($cal.items | Where-Object { $_.day -eq $workDay })
Check ($same.Count -eq 1) "na den odna otmetka: $($same.Count)"
Check ($same[0].source -eq 'deal') "sdelka vazhnee: $($same[0].source)"

Write-Output "`n--- 7. V baze ---"
$row = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT count(*) FROM orders.busy_days WHERE owner_id='$($owner.user.id)'"
Check ([int]$row -eq 1) "svoih otmetok v baze: $row"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: KALENDAR RABOTAET'; exit 0 }
