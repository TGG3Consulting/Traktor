# Skvoznaya proverka tehniki ispolnitelya (TZ 2.5) na nastoyashchey baze:
# chernovik -> shagi vizarda -> validaciya -> publikaciya bez dokumentov ->
# povtornaya otpravka s dokumentami -> chuzhaya tehnika zakryta.
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

Write-Output "`n--- 1. Pustoy spisok ---"
$owner = Login (NewPhone)
$other = Login (NewPhone)

$list = Invoke-RestMethod "$base/v1/equipment/my" -Headers (Bearer $owner.accessToken)
Check (@($list.items).Count -eq 0) "u novogo ispolnitelya tehniki net: $(@($list.items).Count)"

Write-Output "`n--- 2. Chernovik i shagi vizarda ---"
$cat = (Invoke-RestMethod "$base/v1/categories?kind=unit&flat=1").items | Select-Object -First 1
if ($null -eq $cat) { $cat = (Invoke-RestMethod "$base/v1/categories?flat=1").items | Select-Object -First 1 }

$draft = Invoke-RestMethod "$base/v1/equipment/drafts" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ categoryId = $cat.id } | ConvertTo-Json)
Check ($draft.status -eq 'draft') "chernovik sozdan: $($draft.status)"
Check ($draft.draftStep -eq 1) "shag vizarda: $($draft.draftStep)"

$step2 = Invoke-RestMethod "$base/v1/equipment/$($draft.id)" -Method Patch -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{
        brand = 'JCB'; model = '3CX'; year = 2019
        specs = @{ bucket = 0.3; depth = 5.5 }
        priceHour = 12000; priceShift = 80000; minHours = 3; delivery = 15000
        crewSize = 4; crewPrice = 2500
        draftStep = 2
    } | ConvertTo-Json)
Check ($step2.brand -eq 'JCB' -and $step2.model -eq '3CX') "dannye mashiny sohraneny: $($step2.brand) $($step2.model)"
Check ($step2.priceHour -eq 12000) "tarif za chas: $($step2.priceHour)"
Check ($step2.crewSize -eq 4) "brigada: $($step2.crewSize)"

Write-Output "`n--- 3. Bez foto publikovat nelzya ---"
try {
    Invoke-RestMethod "$base/v1/equipment/$($draft.id)/submit" -Method Post -Headers (Hdr $owner.accessToken) | Out-Null
    Check $false 'karto4ka bez foto ne dolzhna prohodit'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 422) 'bez foto otvet 422 s polyami'
}

Write-Output "`n--- 4. Publikaciya bez dokumentov ---"
Invoke-RestMethod "$base/v1/equipment/$($draft.id)" -Method Patch -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ photos = @('photo-1.jpg'); draftStep = 3 } | ConvertTo-Json) | Out-Null
$published = Invoke-RestMethod "$base/v1/equipment/$($draft.id)/submit" -Method Post -Headers (Hdr $owner.accessToken)
Check ($published.status -eq 'unverified') "bez dokumentov - bez proverki, no v rabote: $($published.status)"

$list = Invoke-RestMethod "$base/v1/equipment/my" -Headers (Bearer $owner.accessToken)
Check (@($list.items).Count -eq 1) "tehnika v spiske: $(@($list.items).Count)"
Check ($null -ne $list.items[0].categoryName) 'v kartochke vidno nazvanie kategorii'

Write-Output "`n--- 5. Dokumenty -> proverka ---"
Invoke-RestMethod "$base/v1/equipment/$($draft.id)" -Method Patch -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ docs = @('passport.jpg') } | ConvertTo-Json) | Out-Null
$pending = Invoke-RestMethod "$base/v1/equipment/$($draft.id)/submit" -Method Post -Headers (Hdr $owner.accessToken)
Check ($pending.status -eq 'pending') "s dokumentami uhodit na proverku: $($pending.status)"

$card = Invoke-RestMethod "$base/v1/equipment/$($draft.id)" -Headers (Bearer $owner.accessToken)
Check ($null -eq $card.docs) 'dokumenty naruzhu ne otdayutsya'

Write-Output "`n--- 6. Na proverke pravit nelzya ---"
try {
    Invoke-RestMethod "$base/v1/equipment/$($draft.id)" -Method Patch -Headers (Hdr $owner.accessToken) `
        -ContentType 'application/json' -Body (@{ brand = 'CAT' } | ConvertTo-Json) | Out-Null
    Check $false 'pravka vo vremya proverki ne dolzhna prohodit'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 409) 'pravka vo vremya proverki otklonena (409)'
}

Write-Output "`n--- 7. Chuzhaya tehnika zakryta ---"
try {
    Invoke-RestMethod "$base/v1/equipment/$($draft.id)" -Headers (Bearer $other.accessToken) | Out-Null
    Check $false 'chuzhuyu tehniku videt nelzya'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 403) 'chuzhaya tehnika zakryta (403)'
}
$foreign = Invoke-RestMethod "$base/v1/equipment/my" -Headers (Bearer $other.accessToken)
Check (@($foreign.items).Count -eq 0) 'v chuzhom spiske pusto'

Write-Output "`n--- 8. V baze ---"
$row = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT status, brand, crew_size FROM catalog.equipment WHERE id='$($draft.id)'"
Check ($row -match 'pending\|JCB\|4') "zapis v baze: $row"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: TEHNIKA RABOTAET'; exit 0 }
