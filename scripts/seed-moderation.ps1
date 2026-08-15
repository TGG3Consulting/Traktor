# Kladet v ochered proverki odnu kartochku tehniki dlya ruchnogo prosmotra.
# VNIMANIE: tolko latinitsa.
$ErrorActionPreference = 'Stop'
$base = 'http://127.0.0.1:18080'
function Login($phone) {
    Invoke-RestMethod "$base/v1/auth/otp/start" -Method Post -ContentType 'application/json' `
        -Body (@{ phone = $phone } | ConvertTo-Json) | Out-Null
    return Invoke-RestMethod "$base/v1/auth/otp/verify" -Method Post -ContentType 'application/json' `
        -Headers @{ 'Idempotency-Key' = [guid]::NewGuid().ToString() } `
        -Body (@{ phone = $phone; code = '000000' } | ConvertTo-Json)
}
function Hdr($t) { @{ Authorization = "Bearer $t"; 'Idempotency-Key' = [guid]::NewGuid().ToString() } }

$owner = Login '+37490000002'
$cat = (Invoke-RestMethod "$base/v1/categories?kind=unit&flat=1").items | Select-Object -First 1
$d = Invoke-RestMethod "$base/v1/equipment/drafts" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ categoryId = $cat.id } | ConvertTo-Json)
Invoke-RestMethod "$base/v1/equipment/$($d.id)" -Method Patch -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{
        brand = 'Komatsu'; model = 'PC200'; year = 2021
        photos = @('http://127.0.0.1:19000/traktor-media/demo/excavator.jpg')
        docs = @('http://127.0.0.1:19000/traktor-media/demo/passport.jpg')
    } | ConvertTo-Json) | Out-Null
$res = Invoke-RestMethod "$base/v1/equipment/$($d.id)/submit" -Method Post -Headers (Hdr $owner.accessToken)
Write-Output "v ocheredi: $($res.status) $($d.id)"
