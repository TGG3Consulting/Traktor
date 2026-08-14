# Skvoznaya proverka modulya "Zadaniya" cherez shlyuz na nastoyashchey baze:
# vhod -> spravochnik -> chernovik -> shagi vizarda -> publikatsiya -> lenta ->
# detalka -> skrytiy rezerv -> otmena. Servisy dolzhny byt podnyaty
# (scripts\services-up.ps1).
#
# VNIMANIE: tolko latinitsa - PowerShell 5.1 chitaet .ps1 v ANSI.

$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$base = 'http://127.0.0.1:18080'
$failed = $false

function Check($cond, $msg) {
    if ($cond) { Write-Output "  OK: $msg" } else { Write-Output "  PROVAL: $msg"; $script:failed = $true }
}
function Login($phone) {
    Invoke-RestMethod "$base/v1/auth/otp/start" -Method Post -ContentType 'application/json' `
        -Body (@{ phone = $phone } | ConvertTo-Json) | Out-Null
    return Invoke-RestMethod "$base/v1/auth/otp/verify" -Method Post -ContentType 'application/json' `
        -Headers @{ 'Idempotency-Key' = "jobs-$([guid]::NewGuid())" } `
        -Body (@{ phone = $phone; code = '000000' } | ConvertTo-Json)
}
function Auth($token, $extra) {
    $h = @{ Authorization = "Bearer $token"; 'Idempotency-Key' = "jobs-$([guid]::NewGuid())" }
    if ($extra) { foreach ($k in $extra.Keys) { $h[$k] = $extra[$k] } }
    return $h
}

Write-Output "`n--- 1. Dva uchastnika: zakazchik i ispolnitel ---"
$clientPhone = '+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999)
$ownerPhone  = '+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999)
$client = Login $clientPhone
$owner  = Login $ownerPhone
Check ($client.accessToken -and $owner.accessToken) 'oba voshli po kodu 000000'

Write-Output "`n--- 2. Spravochnik kategoriy ---"
$cats = Invoke-RestMethod "$base/v1/categories?kind=work"
$earth = $cats.items | Where-Object { $_.slug -eq 'work-earth' } | Select-Object -First 1
Check ($cats.items.Count -ge 5) "kategoriy rabot: $($cats.items.Count)"
Check ($null -ne $earth) 'est kategoriya "Kopka / zemlyanye"'
Check ($earth.name.hy -and $earth.name.ru -and $earth.name.en) 'nazvanie na treh yazykah'
Check ($earth.specTemplate.Count -gt 0) "shablon harakteristik: $($earth.specTemplate.Count) poley"

$units = Invoke-RestMethod "$base/v1/categories?kind=unit"
$exc = $units.items | Where-Object { $_.slug -eq 'unit-excavator' } | Select-Object -First 1
Check ($null -ne $exc -and $exc.children.Count -ge 2) 'tehnika otdaetsya derevom (u ekskavatora est ispolneniya)'

Write-Output "`n--- 3. Chernovik i shagi vizarda ---"
$draft = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Auth $client.accessToken) `
    -ContentType 'application/json' -Body (@{
        categoryId = $earth.id
        title      = 'Vykopat transheyu 40 m pod vodoprovod'
        draftStep  = 2
    } | ConvertTo-Json)
Check ($draft.id -and $draft.status -eq 'draft') "chernovik sozdan: $($draft.id)"

$step3 = Invoke-RestMethod "$base/v1/jobs/drafts/$($draft.id)" -Method Patch -Headers (Auth $client.accessToken) `
    -ContentType 'application/json' -Body (@{
        description = 'Transheya vdol zabora, glubina 1,2 m, grunt myagkiy, podezd est.'
        geo         = @{ lat = 40.1872; lng = 44.5152 }
        address     = 'Erevan, Avan'
        access      = 'yes'
        draftStep   = 3
    } | ConvertTo-Json)
Check ($step3.title -eq 'Vykopat transheyu 40 m pod vodoprovod') 'shag 3 ne zatyor dannye shaga 2'

Write-Output "`n--- 4. Publikatsiya bez tseny dolzhna byt otklonena ---"
try {
    Invoke-RestMethod "$base/v1/jobs/$($draft.id)/publish" -Method Post -Headers (Auth $client.accessToken) | Out-Null
    Check $false 'bez tseny publikovat nelzya'
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Check ($code -eq 422) "server otklonil nepolnyy chernovik (kod $code)"
}

Write-Output "`n--- 5. Auktsion: tsena, rezerv, publikatsiya ---"
Invoke-RestMethod "$base/v1/jobs/drafts/$($draft.id)" -Method Patch -Headers (Auth $client.accessToken) `
    -ContentType 'application/json' -Body (@{
        budgetAmount = 120000
        mode         = 'auction'
        auction      = @{ durationH = 24; decisionWindowH = 12; reserveAmount = 70000 }
        draftStep    = 4
    } | ConvertTo-Json) | Out-Null

$published = Invoke-RestMethod "$base/v1/jobs/$($draft.id)/publish" -Method Post -Headers (Auth $client.accessToken)
Check ($published.status -eq 'bidding') "posle publikatsii status: $($published.status)"
Check ($null -ne $published.auction.endsAt) 'server poschital vremya finisha auktsiona'

Write-Output "`n--- 6. Lenta ispolnitelya ---"
$feed = Invoke-RestMethod "$base/v1/jobs?lat=40.18&lng=44.51&radiusKm=25&sort=near" `
    -Headers @{ Authorization = "Bearer $($owner.accessToken)" }
$mine = $feed.items | Where-Object { $_.id -eq $draft.id } | Select-Object -First 1
Check ($null -ne $mine) 'zadanie vidno v lente'
Check ($null -ne $mine.distanceM -and $mine.distanceM -lt 5000) "rasstoyanie poschitano: $([math]::Round($mine.distanceM)) m"

$far = Invoke-RestMethod "$base/v1/jobs?lat=39.0&lng=46.0&radiusKm=10" `
    -Headers @{ Authorization = "Bearer $($owner.accessToken)" }
Check (($far.items | Where-Object { $_.id -eq $draft.id }).Count -eq 0) 'za predelami radiusa zadaniya net'

Write-Output "`n--- 7. Detalka: rezerv skryt ot ispolnitelya ---"
$forOwner  = Invoke-RestMethod "$base/v1/jobs/$($draft.id)" -Headers @{ Authorization = "Bearer $($owner.accessToken)" }
$forClient = Invoke-RestMethod "$base/v1/jobs/$($draft.id)" -Headers @{ Authorization = "Bearer $($client.accessToken)" }
Check ($null -eq $forOwner.auction.reserveAmount) 'ispolnitel ne vidit minimalnuyu tsenu'
Check ($forClient.auction.reserveAmount -eq 70000) 'zakazchik svoyu minimalnuyu tsenu vidit'
Check ($forOwner.viewsCount -ge 1) "prosmotr zaschitan: $($forOwner.viewsCount)"

$again = Invoke-RestMethod "$base/v1/jobs/$($draft.id)" -Headers @{ Authorization = "Bearer $($owner.accessToken)" }
Check ($again.viewsCount -eq $forOwner.viewsCount) 'povtornyy prosmotr tem zhe chelovekom ne nakruchivaet schetchik'

Write-Output "`n--- 8. Chuzhoy chernovik nedostupen ---"
try {
    Invoke-RestMethod "$base/v1/jobs/drafts/$($draft.id)" -Method Patch -Headers (Auth $owner.accessToken) `
        -ContentType 'application/json' -Body (@{ title = 'podmena' } | ConvertTo-Json) | Out-Null
    Check $false 'chuzhoe zadanie menyat nelzya'
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Check ($code -eq 403 -or $code -eq 409) "chuzhoe zadanie zashchishcheno (kod $code)"
}

Write-Output "`n--- 9. Moi zadaniya i otmena ---"
try {
    $my = Invoke-RestMethod "$base/v1/jobs/my" -Headers @{ Authorization = "Bearer $($client.accessToken)" }
    $found = @($my.items | Where-Object { $_.id -eq $draft.id }).Count
    Check ($found -eq 1) "zadanie est v `"moih zadaniyah`" (naydeno: $found, vsego: $(@($my.items).Count))"
} catch {
    Check $false "zapros /v1/jobs/my upal: $($_.Exception.Message)"
}

$cancelled = Invoke-RestMethod "$base/v1/jobs/$($draft.id)/cancel" -Method Post -Headers (Auth $client.accessToken)
Check ($cancelled.status -eq 'cancelled') 'zadanie otmeneno'

$feed2 = Invoke-RestMethod "$base/v1/jobs?lat=40.18&lng=44.51&radiusKm=25" `
    -Headers @{ Authorization = "Bearer $($owner.accessToken)" }
Check (($feed2.items | Where-Object { $_.id -eq $draft.id }).Count -eq 0) 'otmenennoe ushlo iz lenty'

Write-Output "`n--- 10. Dannye perezhivayut perezapusk (chitaem iz bazy) ---"
$row = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT status || '|' || round(ST_Y(geo::geometry)::numeric,4) FROM orders.jobs WHERE id='$($draft.id)'"
Check ($row -match 'cancelled\|40.1872') "v baze: $row"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: MODUL ZADANIY RABOTAET'; exit 0 }
