# Skvoznaya proverka zagruzki fayla (TZ 2.5, ADR-5):
# ssylka -> zagruzka pryamo v hranilishche -> fayl chitaetsya po publichnomu adresu.
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
function NewPhone { '+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999) }

Write-Output "`n--- 1. Ssylka na zagruzku ---"
$user = Login (NewPhone)
$hdr = @{ Authorization = "Bearer $($user.accessToken)"; 'Idempotency-Key' = [guid]::NewGuid().ToString() }

$res = Invoke-RestMethod "$base/v1/media/uploads" -Method Post -Headers $hdr `
    -ContentType 'application/json' -Body (@{ contentType = 'image/jpeg'; folder = 'equipment' } | ConvertTo-Json)
$link = $res.items | Select-Object -First 1
Check ($null -ne $link.uploadUrl) 'vremennaya ssylka vydana'
Check ($link.publicUrl -match 'traktor-media') "publichnyy adres: $($link.publicUrl)"
Check ($link.key -match 'equipment/') "fayl lozhitsya v svoyu papku: $($link.key)"

Write-Output "`n--- 2. Chuzhoy tip ne prinimaem ---"
try {
    Invoke-RestMethod "$base/v1/media/uploads" -Method Post -Headers $hdr `
        -ContentType 'application/json' -Body (@{ contentType = 'application/zip'; folder = 'equipment' } | ConvertTo-Json) | Out-Null
    Check $false 'arhivy gruzit nelzya'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 415) 'chuzhoy tip otklonen (415)'
}

Write-Output "`n--- 3. Zagruzka pryamo v hranilishche ---"
$tmp = Join-Path $env:TEMP 'traktor-test.jpg'
# Minimalnyy JPEG (1x1 piksel) v base64.
$b64 = '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q=='
[IO.File]::WriteAllBytes($tmp, [Convert]::FromBase64String($b64))

$code = curl.exe -s -o NUL -w "%{http_code}" -X PUT -H "Content-Type: image/jpeg" --data-binary "@$tmp" $link.uploadUrl
Check ($code -eq '200') "fayl zagruzhen: HTTP $code"

Write-Output "`n--- 4. Fayl chitaetsya snaruzhi ---"
$read = curl.exe -s -o NUL -w "%{http_code}" $link.publicUrl
Check ($read -eq '200') "publichnoe chtenie: HTTP $read"

Remove-Item $tmp -ErrorAction SilentlyContinue

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: ZAGRUZKA RABOTAET'; exit 0 }
