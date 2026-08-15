# Skvoznaya proverka moderacii tehniki (TZ 4.1) na nastoyashchey baze:
# rol moderatora -> ochered -> odobrenie i otkaz s prichinoy -> uvedomlenie vladelcu.
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

# Etot telefon zadan v services-up.ps1 kak MODERATOR_PHONES.
$moderatorPhone = '+37490000001'

Write-Output "`n--- 1. Rol moderatora vydaetsya po spisku ---"
$moder = Login $moderatorPhone
$owner = Login (NewPhone)
Check ($moder.user.roles -contains 'moderator') "roli moderatora: $($moder.user.roles -join ',')"
Check (-not ($owner.user.roles -contains 'moderator')) "obychnyy polzovatel bez roli: $($owner.user.roles -join ',')"

Write-Output "`n--- 2. Chuzhomu ochered zakryta ---"
try {
    Invoke-RestMethod "$base/v1/moderation/equipment" -Headers (Bearer $owner.accessToken) | Out-Null
    Check $false 'bez roli ochered dolzhna byt zakryta'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 403) 'bez roli otkaz (403)'
}

Write-Output "`n--- 3. Tehnika s dokumentami popadaet v ochered ---"
$cat = (Invoke-RestMethod "$base/v1/categories?kind=unit&flat=1").items | Select-Object -First 1
function NewPending($brand) {
    $d = Invoke-RestMethod "$base/v1/equipment/drafts" -Method Post -Headers (Hdr $owner.accessToken) `
        -ContentType 'application/json' -Body (@{ categoryId = $cat.id } | ConvertTo-Json)
    Invoke-RestMethod "$base/v1/equipment/$($d.id)" -Method Patch -Headers (Hdr $owner.accessToken) `
        -ContentType 'application/json' -Body (@{
            brand = $brand; model = '3CX'; year = 2019
            photos = @('photo-1.jpg'); docs = @('passport.jpg')
        } | ConvertTo-Json) | Out-Null
    return Invoke-RestMethod "$base/v1/equipment/$($d.id)/submit" -Method Post -Headers (Hdr $owner.accessToken)
}
$first  = NewPending 'JCB'
$second = NewPending 'CAT'
Check ($first.status -eq 'pending') "pervaya na proverke: $($first.status)"

$queue = Invoke-RestMethod "$base/v1/moderation/equipment" -Headers (Bearer $moder.accessToken)
$mine = @($queue.items | Where-Object { $_.id -eq $first.id -or $_.id -eq $second.id })
Check ($mine.Count -eq 2) "obe kartochki v ocheredi: $($mine.Count)"
$row = $queue.items | Where-Object { $_.id -eq $first.id }
Check (@($row.docs).Count -eq 1) 'moderator vidit dokumenty'
Check ($null -ne $row.waitingHours) "vidno, skolko zhdet: $($row.waitingHours) ch"

Write-Output "`n--- 4. Odobrenie daet badge ---"
Invoke-RestMethod "$base/v1/moderation/equipment/$($first.id)/approve" -Method Post `
    -Headers (Hdr $moder.accessToken) | Out-Null
$card = Invoke-RestMethod "$base/v1/equipment/$($first.id)" -Headers (Bearer $owner.accessToken)
Check ($card.status -eq 'verified') "status posle odobreniya: $($card.status)"

Write-Output "`n--- 5. Otkaz trebuet prichiny ---"
try {
    Invoke-RestMethod "$base/v1/moderation/equipment/$($second.id)/reject" -Method Post `
        -Headers (Hdr $moder.accessToken) -ContentType 'application/json' `
        -Body (@{ reason = '' } | ConvertTo-Json) | Out-Null
    Check $false 'otkaz bez prichiny ne dolzhen prohodit'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 400) 'otkaz bez prichiny otklonen (400)'
}

Invoke-RestMethod "$base/v1/moderation/equipment/$($second.id)/reject" -Method Post `
    -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
    -Body (@{ reason = 'Документ нечитаем — переснимите при дневном свете' } | ConvertTo-Json) | Out-Null
$rejected = Invoke-RestMethod "$base/v1/equipment/$($second.id)" -Headers (Bearer $owner.accessToken)
Check ($rejected.status -eq 'rejected') "status posle otkaza: $($rejected.status)"
Check ($rejected.rejectReason -match 'нечитаем') "prichina sohranena: $($rejected.rejectReason)"

Write-Output "`n--- 6. Razobrannye kartochki uhodyat iz ocheredi ---"
$queue = Invoke-RestMethod "$base/v1/moderation/equipment" -Headers (Bearer $moder.accessToken)
$left = @($queue.items | Where-Object { $_.id -eq $first.id -or $_.id -eq $second.id })
Check ($left.Count -eq 0) "v ocheredi ne ostalos: $($left.Count)"

Write-Output "`n--- 7. Vladelec uznal o reshenii ---"
Start-Sleep -Milliseconds 600
$feed = Invoke-RestMethod "$base/v1/notifications" -Headers (Bearer $owner.accessToken)
$about = @($feed.items | Where-Object { $_.kind -eq 'equipment' })
Check ($about.Count -ge 2) "uvedomleniy o tehnike: $($about.Count)"

Write-Output "`n--- 8. Povtornoe reshenie nevozmozhno ---"
try {
    Invoke-RestMethod "$base/v1/moderation/equipment/$($first.id)/approve" -Method Post `
        -Headers (Hdr $moder.accessToken) | Out-Null
    Check $false 'odobrennuyu kartochku nelzya odobryat snova'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 409) 'povtornoe reshenie otkloneno (409)'
}

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: MODERACIYA RABOTAET'; exit 0 }
