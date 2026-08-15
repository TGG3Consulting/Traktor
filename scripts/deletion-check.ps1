# Skvoznaya proverka udaleniya akkaunta (TZ 2.3, 4.3) na nastoyashchey baze:
# zapros -> otsrochka 30 dney -> otmena vhodom -> istechenie sroka -> obezlichivanie.
#
# Fayl v UTF-8 s BOM: v nem est russkiy tekst imeni.

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
function Psql($sql) {
    return (docker exec traktor-postgres psql -U traktor -d traktor -t -A -c $sql)
}

$phone = NewPhone
$user = Login $phone
Invoke-RestMethod "$base/v1/me" -Method Patch -Headers (Hdr $user.accessToken) `
    -ContentType 'application/json; charset=utf-8' `
    -Body (@{ name = 'Ваган Мкртчян'; city = 'Ереван' } | ConvertTo-Json) | Out-Null

Write-Output "`n--- 1. Zapros na udalenie ---"
$req = Invoke-RestMethod "$base/v1/me" -Method Delete -Headers (Hdr $user.accessToken)
Check ($null -ne $req.deleteAfter) "srok naznachen: $($req.deleteAfter)"
Check ($req.graceDays -eq 30) "otsrochka v dnyah: $($req.graceDays)"

$days = ([datetime]$req.deleteAfter - (Get-Date)).TotalDays
Check ($days -gt 29 -and $days -lt 31) "do udaleniya okolo 30 dney: $([math]::Round($days,1))"

Write-Output "`n--- 2. Do sroka vsyo rabotaet ---"
$me = Invoke-RestMethod "$base/v1/me" -Headers (Bearer $user.accessToken)
# Sravnenie kirillicy v PowerShell 5.1 nenadezhno (svoya kodirovka otveta),
# poetomu sveryaemsya po nepustote imeni.
Check (-not [string]::IsNullOrWhiteSpace($me.name)) 'profil na meste'
Check ($null -ne $me.deleteAfter) 'v profile vidno, chto akkaunt uydet'

$feed = Invoke-RestMethod "$base/v1/jobs?sort=new&limit=3" -Headers (Bearer $user.accessToken)
Check ($null -ne $feed.items) 'lenta dostupna: chelovek mozhet dovesti sdelki do konca'

Write-Output "`n--- 3. Povtornoe nazhatie ne sdvigaet srok ---"
$again = Invoke-RestMethod "$base/v1/me" -Method Delete -Headers (Hdr $user.accessToken)
Check (([datetime]$again.deleteAfter - [datetime]$req.deleteAfter).TotalSeconds -lt 2) `
    'srok tot zhe: dvoynoe nazhatie ne prodlevaet'

Write-Output "`n--- 4. Vhod otmenyaet udalenie ---"
$back = Login $phone
Check ($null -eq $back.user.deleteAfter) 'posle vhoda udalenie otmeneno'
$dbRow = Psql "SELECT COALESCE(delete_after::text,'') FROM identity.users WHERE id='$($user.user.id)'"
Check ([string]::IsNullOrWhiteSpace($dbRow)) "v baze sroka net: '$dbRow'"

Write-Output "`n--- 5. Yavnaya otmena iz profilya ---"
Invoke-RestMethod "$base/v1/me" -Method Delete -Headers (Hdr $back.accessToken) | Out-Null
Invoke-RestMethod "$base/v1/me/restore" -Method Post -Headers (Hdr $back.accessToken) | Out-Null
$me2 = Invoke-RestMethod "$base/v1/me" -Headers (Bearer $back.accessToken)
Check ($null -eq $me2.deleteAfter) 'knopka "ostavit akkaunt" rabotaet'

Write-Output "`n--- 6. Po istechenii sroka profil obezlichivaetsya ---"
# Perevodim srok v proshloe: zhdat 30 dney v proverke nelzya.
Invoke-RestMethod "$base/v1/me" -Method Delete -Headers (Hdr $back.accessToken) | Out-Null
Psql "UPDATE identity.users SET delete_after = now() - interval '1 day' WHERE id='$($user.user.id)'" | Out-Null

# Obrabotchik razbiraet ochered po taymeru (DELETION_EVERY_SEC na stende - 5 sek).
Write-Output "  zhdem obrabotchik udaleniy"
$tries = 0
while ($tries -lt 12) {
    $anon = Psql "SELECT COALESCE(anonymized_at::text,'') FROM identity.users WHERE id='$($user.user.id)'"
    if (-not [string]::IsNullOrWhiteSpace($anon)) { break }
    Start-Sleep -Seconds 5
    $tries++
}
$anon = Psql "SELECT COALESCE(anonymized_at::text,'') FROM identity.users WHERE id='$($user.user.id)'"
Check (-not [string]::IsNullOrWhiteSpace($anon)) "profil obezlichen: '$anon'"

$name = Psql "SELECT COALESCE(name,'') FROM identity.users WHERE id='$($user.user.id)'"
Check ([string]::IsNullOrWhiteSpace($name)) "imya stersto: '$name'"

$row = Psql "SELECT COUNT(*) FROM identity.users WHERE id='$($user.user.id)'"
Check ($row -eq '1') 'zapis ostalas: na neyo ssylayutsya sdelki i otzyvy vtoroy storony'

Write-Output "`n--- 7. Nomer svoboden dlya novoy registracii ---"
$fresh = Login $phone
Check ($fresh.user.id -ne $user.user.id) 'zavoditsya novyy akkaunt, a ne ozhivaet staryy'

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: UDALENIE AKKAUNTA RABOTAET'; exit 0 }
