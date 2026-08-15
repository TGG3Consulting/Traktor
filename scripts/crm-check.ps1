# Skvoznaya proverka CRM ispolnitelya (TZ 3.1) na nastoyashchey baze:
# dohod za period, voronka i klientskaya baza sobirayutsya iz zavershennyh sdelok.
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

Write-Output "`n--- 1. Novyy ispolnitel: pustaya svodka ---"
$client = Login (NewPhone)
$owner  = Login (NewPhone)
Invoke-RestMethod "$base/v1/me" -Method Patch -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{ name = 'Tigran' } | ConvertTo-Json) | Out-Null

$b = Invoke-RestMethod "$base/v1/crm/business?period=month" -Headers (Bearer $owner.accessToken)
Check ($b.income -eq 0) "dohod: $($b.income)"
Check ($b.deals -eq 0) "sdelok: $($b.deals)"
Check ($b.deltaComparable -eq $false) 'delta bez proshlogo dohoda ne schitaetsya'
Check (@($b.clients).Count -eq 0) 'klientov net'

Write-Output "`n--- 2. Dovodim dve sdelki do konca ---"
$cat = (Invoke-RestMethod "$base/v1/categories?kind=work").items | Select-Object -First 1
function FullDeal($price) {
    $d = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
        -ContentType 'application/json' -Body (@{
            categoryId = $cat.id
            title = 'Rabota dlya proverki CRM'
            description = 'Zadanie, kotoroe dovodim do konca radi cifr v svodke.'
            geo = @{ lat = 40.1872; lng = 44.5152 }
            address = 'Erevan, Avan'
            budgetAmount = $price
            mode = 'fixed'
        } | ConvertTo-Json)
    $job = Invoke-RestMethod "$base/v1/jobs/$($d.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
    $offer = Invoke-RestMethod "$base/v1/jobs/$($job.id)/offers" -Method Post -Headers (Hdr $owner.accessToken) `
        -ContentType 'application/json' -Body (@{ kind = 'accept'; price = $price } | ConvertTo-Json)
    Invoke-RestMethod "$base/v1/offers/$($offer.id)/accept" -Method Post -Headers (Hdr $client.accessToken) | Out-Null
    $deal = Invoke-RestMethod "$base/v1/jobs/$($job.id)/deal" -Method Post -Headers (Hdr $client.accessToken)
    foreach ($step in @(@('on_the_way', $owner), @('in_progress', $owner), @('work_done', $owner), @('completed', $client))) {
        Invoke-RestMethod "$base/v1/deals/$($deal.id)/step" -Method Post -Headers (Hdr $step[1].accessToken) `
            -ContentType 'application/json' -Body (@{ status = $step[0] } | ConvertTo-Json) | Out-Null
    }
}
FullDeal 100000
FullDeal 60000

# Eshche odin otklik, kotoryy nikuda ne privel - dlya voronki.
$d3 = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{
        categoryId = $cat.id
        title = 'Zadanie bez vybora ispolnitelya'
        description = 'Nuzhno, chtoby v voronke byl otklik bez pobedy.'
        geo = @{ lat = 40.1872; lng = 44.5152 }
        address = 'Erevan, Avan'
        budgetAmount = 40000
        mode = 'fixed'
    } | ConvertTo-Json)
$job3 = Invoke-RestMethod "$base/v1/jobs/$($d3.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
Invoke-RestMethod "$base/v1/jobs/$($job3.id)/offers" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ kind = 'accept'; price = 40000 } | ConvertTo-Json) | Out-Null

Write-Output "`n--- 3. Svodka schitaet dohod ---"
$b = Invoke-RestMethod "$base/v1/crm/business?period=month" -Headers (Bearer $owner.accessToken)
Check ($b.income -eq 160000) "dohod za mesyac: $($b.income)"
Check ($b.deals -eq 2) "zavershennyh sdelok: $($b.deals)"
Check ($b.average -eq 80000) "sredniy chek: $($b.average)"

Write-Output "`n--- 4. Voronka ---"
Check ($b.funnel.offers -eq 3) "otklikov: $($b.funnel.offers)"
Check ($b.funnel.won -eq 2) "pobed: $($b.funnel.won)"
Check ($b.funnel.completed -eq 2) "zaversheno: $($b.funnel.completed)"

Write-Output "`n--- 5. Klientskaya baza ---"
$c = $b.clients | Select-Object -First 1
Check (@($b.clients).Count -eq 1) "klientov: $(@($b.clients).Count)"
Check ($c.name -eq 'Tigran') "imya klienta: $($c.name)"
Check ($c.deals -eq 2) "sdelok s nim: $($c.deals)"
Check ($c.total -eq 160000) "summa: $($c.total)"
Check ($c.regular -eq $false) 'postoyannym stanovitsya s tretey sdelki'

Write-Output "`n--- 6. Svodka zakazchika: rashody ---"
$sp = Invoke-RestMethod "$base/v1/crm/spending?period=month" -Headers (Bearer $client.accessToken)
Check ($sp.spent -eq 160000) "potracheno: $($sp.spent)"
Check ($sp.deals -eq 2) "zadaniy: $($sp.deals)"
Check (@($sp.byCategory).Count -ge 1) "kategoriy rashodov: $(@($sp.byCategory).Count)"
Check (@($sp.owners).Count -eq 1) "ispolniteley: $(@($sp.owners).Count)"
Check ($sp.saved -eq 0) "na fiks-cene ekonomii net: $($sp.saved)"

Write-Output "`n--- 7. Chuzhaya svodka nedostupna ---"
$foreign = Invoke-RestMethod "$base/v1/crm/business?period=month" -Headers (Bearer $client.accessToken)
Check ($foreign.income -eq 0) "u zakazchika svoya svodka ispolnitelya pustaya: $($foreign.income)"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: CRM RABOTAET'; exit 0 }
