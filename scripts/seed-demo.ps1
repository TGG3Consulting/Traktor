# Demo-dannye dlya ruchnoy proverki v brauzere.
#
# Sozdaet paru "zakazchik + ispolnitel" s postoyannymi nomerami, zadanie s
# perepiskoy, zavershennuyu sdelku (dlya ekrana ocenki) i neskolko sobytiy v
# centre uvedomleniy. Vhod v prilozhenie - po etim nomeram, kod 000000.
#
# VNIMANIE: tolko latinitsa - PowerShell 5.1 chitaet .ps1 v ANSI.

$ErrorActionPreference = 'Stop'
$base = 'http://127.0.0.1:18080'

# Postoyannye nomera: posle povtornogo zapuska voyti mozhno temi zhe.
$clientPhone = '+37490000001'
$ownerPhone  = '+37490000002'

function Login($phone) {
    Invoke-RestMethod "$base/v1/auth/otp/start" -Method Post -ContentType 'application/json' `
        -Body (@{ phone = $phone } | ConvertTo-Json) | Out-Null
    return Invoke-RestMethod "$base/v1/auth/otp/verify" -Method Post -ContentType 'application/json' `
        -Headers @{ 'Idempotency-Key' = [guid]::NewGuid().ToString() } `
        -Body (@{ phone = $phone; code = '000000' } | ConvertTo-Json)
}
function Hdr($t) { @{ Authorization = "Bearer $t"; 'Idempotency-Key' = [guid]::NewGuid().ToString() } }
function Json { 'application/json; charset=utf-8' }

$client = Login $clientPhone
$owner  = Login $ownerPhone
Invoke-RestMethod "$base/v1/me" -Method Patch -Headers (Hdr $client.accessToken) `
    -ContentType (Json) -Body (@{ name = 'Tigran' } | ConvertTo-Json) | Out-Null
Invoke-RestMethod "$base/v1/me" -Method Patch -Headers (Hdr $owner.accessToken) `
    -ContentType (Json) -Body (@{ name = 'Karen Sarkisyan' } | ConvertTo-Json) | Out-Null

$cat = (Invoke-RestMethod "$base/v1/categories?kind=work").items | Select-Object -First 1

function NewJob($title, $desc, $price) {
    $d = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
        -ContentType (Json) -Body (@{
            categoryId   = $cat.id
            title        = $title
            description  = $desc
            geo          = @{ lat = 40.1872; lng = 44.5152 }
            address      = 'Erevan, Avan'
            budgetAmount = $price
            mode         = 'fixed'
        } | ConvertTo-Json)
    return Invoke-RestMethod "$base/v1/jobs/$($d.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
}

# 1. Zadanie s perepiskoy do sdelki: vidno maskirovku kontaktov.
$job1 = NewJob 'Planirovka uchastka 6 sotok' 'Vyrovnyat uchastok pod gazon, gruntovye raboty.' 85000
$chat = Invoke-RestMethod "$base/v1/jobs/$($job1.id)/chat" -Method Post -Headers (Hdr $owner.accessToken)
Invoke-RestMethod "$base/v1/chats/$($chat.id)/messages" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType (Json) -Body (@{ text = 'Здравствуйте! Подъезд для техники есть?' } | ConvertTo-Json) | Out-Null
Invoke-RestMethod "$base/v1/chats/$($chat.id)/messages" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType (Json) -Body (@{ text = 'Да, ворота 3 метра, заезжайте со двора' } | ConvertTo-Json) | Out-Null
Invoke-RestMethod "$base/v1/chats/$($chat.id)/messages" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType (Json) -Body (@{ text = 'Отлично, наберите меня +374 91 234 567' } | ConvertTo-Json) | Out-Null
Invoke-RestMethod "$base/v1/jobs/$($job1.id)/offers" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType (Json) -Body (@{ kind = 'accept'; price = 85000 } | ConvertTo-Json) | Out-Null

# 2. Zavershennaya sdelka: otkryt ekran ocenki.
$job2 = NewJob 'Vyvezti stroitelnyy musor 12 t' 'Samosval i dva gruzchika, talon na poligon vklyuchen.' 70000
$offer2 = Invoke-RestMethod "$base/v1/jobs/$($job2.id)/offers" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType (Json) -Body (@{ kind = 'accept'; price = 70000 } | ConvertTo-Json)
Invoke-RestMethod "$base/v1/offers/$($offer2.id)/accept" -Method Post -Headers (Hdr $client.accessToken) | Out-Null
$deal = Invoke-RestMethod "$base/v1/jobs/$($job2.id)/deal" -Method Post -Headers (Hdr $client.accessToken)
foreach ($step in @(@('on_the_way', $owner), @('in_progress', $owner), @('work_done', $owner), @('completed', $client))) {
    Invoke-RestMethod "$base/v1/deals/$($deal.id)/step" -Method Post -Headers (Hdr $step[1].accessToken) `
        -ContentType (Json) -Body (@{ status = $step[0] } | ConvertTo-Json) | Out-Null
}

Write-Output ''
Write-Output 'Demo-dannye gotovy.'
Write-Output "  Zakazchik:   $clientPhone  (kod 000000)"
Write-Output "  Ispolnitel:  $ownerPhone  (kod 000000)"
Write-Output "  Chat:        /chats/$($chat.id)"
Write-Output "  Sdelka:      /deals/$($deal.id)  -> ekran ocenki /deals/$($deal.id)/review"
