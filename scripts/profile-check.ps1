# Skvoznaya proverka kartochki cheloveka (TZ 2.3) na nastoyashchey baze:
# imya i gorod otkryty bez vhoda, telefon ne otdaetsya nikogda,
# tehnika i otzyvy vidny v kartochke.
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

Write-Output "`n--- 1. Kartochka otkryta bez vhoda ---"
$owner = Login (NewPhone)
Invoke-RestMethod "$base/v1/me" -Method Patch -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json; charset=utf-8' `
    -Body (@{ name = 'Karen Sarkisyan'; city = 'Erevan' } | ConvertTo-Json) | Out-Null

$card = Invoke-RestMethod "$base/v1/users/$($owner.user.id)"
Check ($card.name -eq 'Karen Sarkisyan') "imya v kartochke: $($card.name)"
Check ($card.city -eq 'Erevan') "gorod: $($card.city)"
Check ($null -eq $card.phone) 'telefon v kartochke ne otdaetsya'

Write-Output "`n--- 2. Tehnika v kartochke ---"
$cat = (Invoke-RestMethod "$base/v1/categories?kind=unit&flat=1").items | Select-Object -First 1
$draft = Invoke-RestMethod "$base/v1/equipment/drafts" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ categoryId = $cat.id } | ConvertTo-Json)
Invoke-RestMethod "$base/v1/equipment/$($draft.id)" -Method Patch -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{
        brand = 'JCB'; model = '3CX'; year = 2019; photos = @('photo-1.jpg')
    } | ConvertTo-Json) | Out-Null

# Do publikacii tehniki v kartochke net.
$before = Invoke-RestMethod "$base/v1/equipment/users/$($owner.user.id)"
Check (@($before.items).Count -eq 0) "chernovik v kartochke ne pokazyvaem: $(@($before.items).Count)"

Invoke-RestMethod "$base/v1/equipment/$($draft.id)/submit" -Method Post -Headers (Hdr $owner.accessToken) | Out-Null
$after = Invoke-RestMethod "$base/v1/equipment/users/$($owner.user.id)"
$row = $after.items | Select-Object -First 1
Check (@($after.items).Count -eq 1) "opublikovannaya tehnika vidna: $(@($after.items).Count)"
Check ($row.title -eq 'JCB 3CX') "nazvanie mashiny: $($row.title)"
Check ($null -eq $row.priceHour) 'tarify v publichnoy kartochke ne otdaem'

Write-Output "`n--- 3. Snyataya tehnika propadaet iz kartochki ---"
Invoke-RestMethod "$base/v1/equipment/$($draft.id)/archive" -Method Post -Headers (Hdr $owner.accessToken) | Out-Null
$archived = Invoke-RestMethod "$base/v1/equipment/users/$($owner.user.id)"
Check (@($archived.items).Count -eq 0) "snyataya mashina skryta: $(@($archived.items).Count)"

Write-Output "`n--- 4. Nesushchestvuyushchiy polzovatel ---"
try {
    Invoke-RestMethod "$base/v1/users/00000000-0000-0000-0000-000000000000" | Out-Null
    Check $false 'dolzhen byt 404'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 404) 'net takogo polzovatelya (404)'
}

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: KARTOCHKA RABOTAET'; exit 0 }
