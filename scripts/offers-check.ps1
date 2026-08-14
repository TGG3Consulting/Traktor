# Skvoznaya proverka otklikov (TZ 2.10) cherez shlyuz na nastoyashchey baze:
# publikatsiya s fiks-tsenoy -> dva ispolnitelya otklikayutsya -> vstrechnaya
# tsena -> vybor -> ostalnye otkloneny -> zadanie zhdet podtverzhdeniya.
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
        -Headers @{ 'Idempotency-Key' = "off-$([guid]::NewGuid())" } `
        -Body (@{ phone = $phone; code = '000000' } | ConvertTo-Json)
}
function Auth($token) {
    return @{ Authorization = "Bearer $token"; 'Idempotency-Key' = "off-$([guid]::NewGuid())" }
}
function NewPhone { '+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999) }

Write-Output "`n--- 1. Zakazchik i dva ispolnitelya ---"
$client = Login (NewPhone)
$ownerA = Login (NewPhone)
$ownerB = Login (NewPhone)
Check ($client.accessToken -and $ownerA.accessToken -and $ownerB.accessToken) 'vse voshli'

Write-Output "`n--- 2. Zadanie s fiksirovannoy tsenoy ---"
$cats = Invoke-RestMethod "$base/v1/categories?kind=work"
$earth = $cats.items | Where-Object { $_.slug -eq 'work-earth' } | Select-Object -First 1
$draft = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Auth $client.accessToken) `
    -ContentType 'application/json' -Body (@{
        categoryId   = $earth.id
        title        = 'Vyvezti stroitelnyy musor'
        description  = 'Posle demontazha peregorodok, primerno 12 tonn, pogruzka moya.'
        geo          = @{ lat = 40.1872; lng = 44.5152 }
        address      = 'Erevan, Arabkir'
        budgetAmount = 45000
        mode         = 'fixed'
        draftStep    = 5
    } | ConvertTo-Json)
$job = Invoke-RestMethod "$base/v1/jobs/$($draft.id)/publish" -Method Post -Headers (Auth $client.accessToken)
Check ($job.status -eq 'collecting_offers') "zadanie sobiraet otkliki: $($job.status)"

Write-Output "`n--- 3. Otkliki ispolniteley ---"
$offerA = Invoke-RestMethod "$base/v1/jobs/$($job.id)/offers" -Method Post -Headers (Auth $ownerA.accessToken) `
    -ContentType 'application/json' -Body (@{ kind = 'accept'; price = 1; eta = 'zavtra s utra' } | ConvertTo-Json)
Check ($offerA.price -eq 45000) "pri soglasii tsena beretsya s servera: $($offerA.price)"

$offerB = Invoke-RestMethod "$base/v1/jobs/$($job.id)/offers" -Method Post -Headers (Auth $ownerB.accessToken) `
    -ContentType 'application/json' -Body (@{ kind = 'counter'; price = 38000; comment = 'Sdelayu za den' } | ConvertTo-Json)
Check ($offerB.kind -eq 'counter' -and $offerB.price -eq 38000) 'vstrechnoe predlozhenie sozdano'

$withJob = Invoke-RestMethod "$base/v1/jobs/$($job.id)" -Headers @{ Authorization = "Bearer $($client.accessToken)" }
Check ($withJob.offersCount -eq 2) "schetchik otklikov: $($withJob.offersCount)"

Write-Output "`n--- 4. Povtornyy otklik obnovlyaet, a ne dubliruet ---"
$again = Invoke-RestMethod "$base/v1/jobs/$($job.id)/offers" -Method Post -Headers (Auth $ownerB.accessToken) `
    -ContentType 'application/json' -Body (@{ kind = 'counter'; price = 40000 } | ConvertTo-Json)
Check ($again.id -eq $offerB.id -and $again.price -eq 40000) 'predlozhenie obnovleno bez dublya'

Write-Output "`n--- 5. Chuzhoy spisok otklikov zakryt ---"
try {
    Invoke-RestMethod "$base/v1/jobs/$($job.id)/offers" -Headers @{ Authorization = "Bearer $($ownerA.accessToken)" } | Out-Null
    Check $false 'ispolnitel ne dolzhen videt chuzhie otkliki'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 403) 'spisok otklikov vidit tolko zakazchik'
}

Write-Output "`n--- 6. Vstrechnaya tsena zakazchika (odin raund) ---"
$countered = Invoke-RestMethod "$base/v1/offers/$($offerB.id)/counter" -Method Post -Headers (Auth $client.accessToken) `
    -ContentType 'application/json' -Body (@{ price = 42000 } | ConvertTo-Json)
Check ($countered.status -eq 'counter_offered' -and $countered.clientCounterPrice -eq 42000) 'vstrechnaya tsena otpravlena'

try {
    Invoke-RestMethod "$base/v1/offers/$($offerB.id)/counter" -Method Post -Headers (Auth $client.accessToken) `
        -ContentType 'application/json' -Body (@{ price = 41000 } | ConvertTo-Json) | Out-Null
    Check $false 'vtoroy raund torga dolzhen byt zapreshchen'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 409) 'vtoroy raund torga otklonen (409)'
}

Write-Output "`n--- 7. Vybor ispolnitelya ---"
$accepted = Invoke-RestMethod "$base/v1/offers/$($offerB.id)/accept" -Method Post -Headers (Auth $client.accessToken)
Check ($accepted.status -eq 'accepted') 'predlozhenie prinyato'
Check ($accepted.price -eq 42000) "deystvuet vstrechnaya tsena: $($accepted.price)"

$offers = Invoke-RestMethod "$base/v1/jobs/$($job.id)/offers" -Headers @{ Authorization = "Bearer $($client.accessToken)" }
$a = $offers.items | Where-Object { $_.id -eq $offerA.id } | Select-Object -First 1
Check ($a.status -eq 'declined') "ostalnye otkloneny avtomaticheski: $($a.status)"

$final = Invoke-RestMethod "$base/v1/jobs/$($job.id)" -Headers @{ Authorization = "Bearer $($client.accessToken)" }
Check ($final.status -eq 'deal_pending') "zadanie zhdet podtverzhdeniya: $($final.status)"

Write-Output "`n--- 8. Moi predlozheniya ispolnitelya ---"
$mine = Invoke-RestMethod "$base/v1/offers/my" -Headers @{ Authorization = "Bearer $($ownerB.accessToken)" }
Check (@($mine.items).Count -ge 1) "u ispolnitelya vidny ego predlozheniya: $(@($mine.items).Count)"

$myOne = Invoke-RestMethod "$base/v1/jobs/$($job.id)/offers/my" -Headers @{ Authorization = "Bearer $($ownerA.accessToken)" }
Check ($null -ne $myOne.offer) 'svoy otklik chitaetsya po zadaniyu'

Write-Output "`n--- 9. V baze ---"
$row = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT count(*) FROM orders.offers WHERE job_id='$($job.id)'"
Check ([int]$row -eq 2) "otklikov v baze: $row"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: OTKLIKI RABOTAYUT'; exit 0 }
