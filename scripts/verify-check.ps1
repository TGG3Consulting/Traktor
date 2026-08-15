# Skvoznaya proverka bejdzha "Proveren" (TZ 2.3) na nastoyashchey baze:
# podacha dokumenta -> ochered moderacii -> otkaz s prichinoy -> povtor -> bejdzh.
#
# Fayl v UTF-8 s BOM: v nem est russkie prichiny otkaza.

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

$moder = Login '+37490000001'
$phone = NewPhone
$user  = Login $phone

Write-Output "`n--- 1. Bez imeni proveryat nechego ---"
try {
    Invoke-RestMethod "$base/v1/me/verification" -Method Post -Headers (Hdr $user.accessToken) `
        -ContentType 'application/json; charset=utf-8' `
        -Body (@{ docKind = 'passport'; documents = @('https://media.local/doc1.jpg') } | ConvertTo-Json) | Out-Null
    Check $false 'dokument ne s chem sverit'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 400) 'bez imeni zayavka otklonena (400)'
}

Invoke-RestMethod "$base/v1/me" -Method Patch -Headers (Hdr $user.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{ name = 'Карен Петросян' } | ConvertTo-Json) | Out-Null

Write-Output "`n--- 2. Bez dokumenta zayavka ne prinimaetsya ---"
try {
    Invoke-RestMethod "$base/v1/me/verification" -Method Post -Headers (Hdr $user.accessToken) `
        -ContentType 'application/json; charset=utf-8' `
        -Body (@{ docKind = 'passport'; documents = @() } | ConvertTo-Json) | Out-Null
    Check $false 'moderatoru nuzhno chto-to smotret'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 400) 'zayavka bez fayla otklonena (400)'
}

Write-Output "`n--- 3. Zayavka podana ---"
$v = Invoke-RestMethod "$base/v1/me/verification" -Method Post -Headers (Hdr $user.accessToken) `
    -ContentType 'application/json; charset=utf-8' `
    -Body (@{ docKind = 'passport'; documents = @('https://media.local/doc1.jpg') } | ConvertTo-Json)
Check ($v.status -eq 'pending') "zayavka zhdet moderacii: $($v.status)"

$mine = Invoke-RestMethod "$base/v1/me/verification" -Headers (Bearer $user.accessToken)
Check ($mine.status -eq 'pending') 'ekran profilya vidit sostoyanie proverki'

Write-Output "`n--- 4. Vtoraya zayavka ne udlinyaet ochered ---"
try {
    Invoke-RestMethod "$base/v1/me/verification" -Method Post -Headers (Hdr $user.accessToken) `
        -ContentType 'application/json; charset=utf-8' `
        -Body (@{ docKind = 'license'; documents = @('https://media.local/doc2.jpg') } | ConvertTo-Json) | Out-Null
    Check $false 'odna zayavka v rabote'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 409) 'povtornaya zayavka otklonena (409)'
}

Write-Output "`n--- 5. Ochered moderacii ---"
$queue = Invoke-RestMethod "$base/v1/moderation/verifications" -Headers (Bearer $moder.accessToken)
$row = $queue.items | Where-Object { $_.id -eq $v.id }
Check ($null -ne $row) 'zayavka v ocheredi'
Check ($row.userPhone -eq $phone) "moderator sveryaet s profilem: $($row.userPhone)"
Check ($row.documents.Count -eq 1) "snimki na meste: $($row.documents.Count)"

try {
    Invoke-RestMethod "$base/v1/moderation/verifications" -Headers (Bearer $user.accessToken) | Out-Null
    Check $false 'ochered dostupna tolko moderacii'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 403) 'bez roli ochered zakryta (403)'
}

Write-Output "`n--- 6. Otkaz trebuet prichiny ---"
try {
    Invoke-RestMethod "$base/v1/moderation/verifications/$($v.id)/review" -Method Post `
        -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
        -Body (@{ approve = $false; reason = 'нет' } | ConvertTo-Json) | Out-Null
    Check $false 'chelovek dolzhen ponyat, chto peresnyat'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 400) 'otkaz bez obyasneniya otklonen (400)'
}

Write-Output "`n--- 7. Otkaz s prichinoy ---"
$rejected = Invoke-RestMethod "$base/v1/moderation/verifications/$($v.id)/review" -Method Post `
    -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
    -Body (@{ approve = $false; reason = 'Снимок засвечен, номер документа не читается' } | ConvertTo-Json)
Check ($rejected.status -eq 'rejected') "zayavka otklonena: $($rejected.status)"

$me = Invoke-RestMethod "$base/v1/me" -Headers (Bearer $user.accessToken)
Check ($me.verified -eq $false) 'posle otkaza bejdzha net'

Write-Output "`n--- 8. Povtornaya podacha posle otkaza ---"
$v2 = Invoke-RestMethod "$base/v1/me/verification" -Method Post -Headers (Hdr $user.accessToken) `
    -ContentType 'application/json; charset=utf-8' `
    -Body (@{ docKind = 'passport'; documents = @('https://media.local/doc-new.jpg') } | ConvertTo-Json)
Check ($v2.status -eq 'pending') 'posle otkaza mozhno peresnyat i podat snova'

Write-Output "`n--- 9. Odobrenie vydaet bejdzh ---"
$approved = Invoke-RestMethod "$base/v1/moderation/verifications/$($v2.id)/review" -Method Post `
    -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
    -Body (@{ approve = $true } | ConvertTo-Json)
Check ($approved.status -eq 'approved') "zayavka odobrena: $($approved.status)"

$me2 = Invoke-RestMethod "$base/v1/me" -Headers (Bearer $user.accessToken)
Check ($me2.verified -eq $true) 'bejdzh poyavilsya v profile'

$card = Invoke-RestMethod "$base/v1/users/$($user.user.id)"
Check ($card.verified -eq $true) 'bejdzh viden v chuzhoy kartochke'

Write-Output "`n--- 10. Proverennomu povtorno ne nuzhno ---"
try {
    Invoke-RestMethod "$base/v1/me/verification" -Method Post -Headers (Hdr $user.accessToken) `
        -ContentType 'application/json; charset=utf-8' `
        -Body (@{ docKind = 'passport'; documents = @('https://media.local/doc3.jpg') } | ConvertTo-Json) | Out-Null
    Check $false 'rabota moderacii vpustuyu'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 409) 'zayavka proverennogo otklonena (409)'
}

Write-Output "`n--- 11. Reshenie v zhurnale moderacii ---"
$cardAdmin = Invoke-RestMethod "$base/v1/moderation/users/$($user.user.id)" -Headers (Bearer $moder.accessToken)
Check (@($cardAdmin.history | Where-Object { $_.action -like 'verify:*' }).Count -ge 2) `
    "resheniya o doverii v zhurnale: $(@($cardAdmin.history | Where-Object { $_.action -like 'verify:*' }).Count)"

Write-Output "`n--- 12. V baze ---"
$row = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT status FROM identity.verifications WHERE id='$($v2.id)'"
Check ($row -match 'approved') "zapis v baze: $row"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: PROVERKA LYUDEY RABOTAET'; exit 0 }
