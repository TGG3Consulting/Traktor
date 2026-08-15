# Skvoznaya proverka otzyvov (TZ 2.13) na nastoyashchey baze:
# sdelka do zaversheniya -> pervaya otsenka skryta -> vstrechnaya otkryvaet obe ->
# reyting v kartochke -> otvet na otzyv odin raz.
#
# VNIMANIE: fayl sohranen v UTF-8 s BOM - v nem est kirillicheskie tegi ocenok.
# Bez BOM PowerShell 5.1 prochital by ih kak ANSI-musor.
# Telo zaprosov otpravlyaem s charset=utf-8: inache PS 5.1 shlet ISO-8859-1
# i server vidit vmesto "Пунктуально" nabor voprositelnyh znakov.

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

Write-Output "`n--- 1. Dovodim sdelku do zaversheniya ---"
$client = Login (NewPhone)
$owner  = Login (NewPhone)

Invoke-RestMethod "$base/v1/me" -Method Patch -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{ name = 'Tigran' } | ConvertTo-Json) | Out-Null
Invoke-RestMethod "$base/v1/me" -Method Patch -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{ name = 'Karen Sarkisyan' } | ConvertTo-Json) | Out-Null

$cat = (Invoke-RestMethod "$base/v1/categories?kind=work").items | Select-Object -First 1
$draft = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{
        categoryId   = $cat.id
        title        = 'Planirovka uchastka 6 sotok'
        description  = 'Vyrovnyat uchastok pod gazon, gruntovye raboty, tehnika svoya.'
        geo          = @{ lat = 40.1872; lng = 44.5152 }
        address      = 'Erevan, Avan'
        budgetAmount = 85000
        mode         = 'fixed'
    } | ConvertTo-Json)
$job = Invoke-RestMethod "$base/v1/jobs/$($draft.id)/publish" -Method Post -Headers (Hdr $client.accessToken)

$offer = Invoke-RestMethod "$base/v1/jobs/$($job.id)/offers" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{ kind = 'accept'; price = 85000 } | ConvertTo-Json)
Invoke-RestMethod "$base/v1/offers/$($offer.id)/accept" -Method Post -Headers (Hdr $client.accessToken) | Out-Null
$deal = Invoke-RestMethod "$base/v1/jobs/$($job.id)/deal" -Method Post -Headers (Hdr $client.accessToken)

# Do zaversheniya otsenka nedostupna.
$form = Invoke-RestMethod "$base/v1/deals/$($deal.id)/review" -Headers (Bearer $client.accessToken)
Check ($form.canReview -eq $false) 'do zaversheniya ocenivat nechego'

foreach ($step in @(@('on_the_way', $owner), @('in_progress', $owner), @('work_done', $owner), @('completed', $client))) {
    $tok = $step[1].accessToken
    Invoke-RestMethod "$base/v1/deals/$($deal.id)/step" -Method Post -Headers (Hdr $tok) `
        -ContentType 'application/json; charset=utf-8' -Body (@{ status = $step[0] } | ConvertTo-Json) | Out-Null
}
$done = Invoke-RestMethod "$base/v1/deals/$($deal.id)" -Headers (Bearer $client.accessToken)
Check ($done.status -eq 'completed') "sdelka zavershena: $($done.status)"

Write-Output "`n--- 2. Forma ocenki znaet rol i otmetki ---"
$form = Invoke-RestMethod "$base/v1/deals/$($deal.id)/review" -Headers (Bearer $client.accessToken)
Check ($form.canReview -eq $true) 'zakazchik mozhet ocenit'
Check ($form.authorRole -eq 'client') "rol avtora: $($form.authorRole)"
Check ($form.allowedTags -contains 'Пунктуально') 'otmetki dlya ocenki ispolnitelya'
Check ($form.targetName -eq 'Karen Sarkisyan') "imya vtoroy storony: $($form.targetName)"

$formOwner = Invoke-RestMethod "$base/v1/deals/$($deal.id)/review" -Headers (Bearer $owner.accessToken)
Check ($formOwner.allowedTags -contains 'Чёткое ТЗ') 'ispolnitelyu - otmetki pro zakazchika'

Write-Output "`n--- 3. Pervaya ocenka skryta ---"
$first = Invoke-RestMethod "$base/v1/deals/$($deal.id)/review" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{
        stars = 5; tags = @('Пунктуально', 'Аккуратно'); text = 'Priehal vovremya, uchastok vyrovnyal idealno'
    } | ConvertTo-Json)
Check ($first.published -eq $false) 'odinokaya ocenka ne publikuetsya srazu'

$about = Invoke-RestMethod "$base/v1/reviews/users/$($owner.user.id)" -Headers (Bearer $client.accessToken)
Check (@($about.items).Count -eq 0) "skrytyy otzyv ne vidno: $(@($about.items).Count)"

Write-Output "`n--- 4. Povtornaya ocenka otklonyaetsya ---"
try {
    Invoke-RestMethod "$base/v1/deals/$($deal.id)/review" -Method Post -Headers (Hdr $client.accessToken) `
        -ContentType 'application/json; charset=utf-8' -Body (@{ stars = 1 } | ConvertTo-Json) | Out-Null
    Check $false 'vtoraya ocenka ne dolzhna prohodit'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 409) 'vtoraya ocenka po toy zhe sdelke otklonena (409)'
}

Write-Output "`n--- 5. Vstrechnaya ocenka otkryvaet obe ---"
$second = Invoke-RestMethod "$base/v1/deals/$($deal.id)/review" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{
        stars = 4; tags = @('Чёткое ТЗ', 'Оплата без проблем')
    } | ConvertTo-Json)
Check ($second.published -eq $true) 'vtoraya ocenka publikuetsya srazu'

$aboutOwner = Invoke-RestMethod "$base/v1/reviews/users/$($owner.user.id)" -Headers (Bearer $client.accessToken)
Check (@($aboutOwner.items).Count -eq 1) "otzyv ob ispolnitele otkrylsya: $(@($aboutOwner.items).Count)"
Check ($aboutOwner.rating -eq 5) "reyting ispolnitelya: $($aboutOwner.rating)"
Check ($aboutOwner.items[0].authorName -eq 'Tigran') "vidno imya avtora: $($aboutOwner.items[0].authorName)"

$aboutClient = Invoke-RestMethod "$base/v1/reviews/users/$($client.user.id)" -Headers (Bearer $owner.accessToken)
Check (@($aboutClient.items).Count -eq 1) 'otzyv o zakazchike otkrylsya vmeste s nim'
Check ($aboutClient.rating -eq 4) "reyting zakazchika: $($aboutClient.rating)"

Write-Output "`n--- 6. Nizkaya ocenka sprashivaet, chto poshlo ne tak ---"
Check ($first.asksWhatWentWrong -eq $false) 'na pyat zvezd lishnih voprosov net'

Write-Output "`n--- 7. Otvet na otzyv - odin raz ---"
$reviewId = $aboutOwner.items[0].id
try {
    Invoke-RestMethod "$base/v1/reviews/$reviewId/reply" -Method Post -Headers (Hdr $client.accessToken) `
        -ContentType 'application/json; charset=utf-8' -Body (@{ text = 'ne moy otzyv' } | ConvertTo-Json) | Out-Null
    Check $false 'otvechat mozhet tolko tot, kogo ocenili'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 403) 'chuzhoy otzyv kommentirovat nelzya (403)'
}
$replied = Invoke-RestMethod "$base/v1/reviews/$reviewId/reply" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{ text = 'Spasibo za otzyv, bylo priyatno rabotat!' } | ConvertTo-Json)
Check ($replied.replyText -match 'Spasibo') 'otvet sohranen'
try {
    Invoke-RestMethod "$base/v1/reviews/$reviewId/reply" -Method Post -Headers (Hdr $owner.accessToken) `
        -ContentType 'application/json; charset=utf-8' -Body (@{ text = 'i eshche' } | ConvertTo-Json) | Out-Null
    Check $false 'vtoroy otvet ne dolzhen prohodit'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 409) 'vtoroy otvet otklonen (409)'
}

Write-Output "`n--- 8. Reyting popal v kartochku otklika ---"
$draft2 = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{
        categoryId   = $cat.id
        title        = 'Vtoroe zadanie dlya proverki reytinga'
        description  = 'Proveryaem, chto reyting ispolnitelya viden v kartochke otklika.'
        geo          = @{ lat = 40.1872; lng = 44.5152 }
        address      = 'Erevan, Avan'
        budgetAmount = 50000
        mode         = 'fixed'
    } | ConvertTo-Json)
$job2 = Invoke-RestMethod "$base/v1/jobs/$($draft2.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
Invoke-RestMethod "$base/v1/jobs/$($job2.id)/offers" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{ kind = 'accept'; price = 50000 } | ConvertTo-Json) | Out-Null
$offers = Invoke-RestMethod "$base/v1/jobs/$($job2.id)/offers" -Headers (Bearer $client.accessToken)
$row = $offers.items | Select-Object -First 1
Check ($row.ownerRating -eq 5) "v kartochke otklika reyting: $($row.ownerRating)"
Check ($row.ownerRatingCount -eq 1) "chislo ocenok: $($row.ownerRatingCount)"

Write-Output "`n--- 9. V baze ---"
$cnt = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT count(*) FROM orders.reviews WHERE deal_id='$($deal.id)'"
Check ([int]$cnt -eq 2) "otzyvov v baze: $cnt"
$pub = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT count(*) FROM orders.reviews WHERE deal_id='$($deal.id)' AND published_at IS NOT NULL"
Check ([int]$pub -eq 2) "opublikovano: $pub"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: OTZYVY RABOTAYUT'; exit 0 }
