# Sozdaet auktsion s odnoy stavkoy - chtoby posmotret ekran torga glazami.
$ErrorActionPreference = 'Continue'
$base = 'http://127.0.0.1:18080'
function Login($phone) {
    Invoke-RestMethod "$base/v1/auth/otp/start" -Method Post -ContentType 'application/json' `
        -Body (@{ phone = $phone } | ConvertTo-Json) | Out-Null
    return Invoke-RestMethod "$base/v1/auth/otp/verify" -Method Post -ContentType 'application/json' `
        -Headers @{ 'Idempotency-Key' = [guid]::NewGuid().ToString() } `
        -Body (@{ phone = $phone; code = '000000' } | ConvertTo-Json)
}
function Hdr($t) { @{ Authorization = "Bearer $t"; 'Idempotency-Key' = [guid]::NewGuid().ToString() } }

$client = Login '+37493000777'
$rival  = Login '+37493000888'
$cat = (Invoke-RestMethod "$base/v1/categories?kind=work").items | Where-Object { $_.slug -eq 'work-earth' } | Select-Object -First 1
$draft = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{
        categoryId   = $cat.id
        title        = 'Vykopat transheyu 60 m pod kabel'
        description  = 'Transheya vdol dorogi, glubina 0,8 m, grunt srednyy, est podezd.'
        geo          = @{ lat = 40.1900; lng = 44.5200 }
        address      = 'Erevan, Kanaker'
        budgetAmount = 150000
        mode         = 'auction'
        auction      = @{ durationH = 24; decisionWindowH = 12 }
    } | ConvertTo-Json)
$job = Invoke-RestMethod "$base/v1/jobs/$($draft.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
Invoke-RestMethod "$base/v1/jobs/$($job.id)/bids" -Method Post -Headers (Hdr $rival.accessToken) `
    -ContentType 'application/json' -Body (@{ price = 130000; comment = 'Ekskavator, dva dnya' } | ConvertTo-Json) | Out-Null
Write-Output "auktsion: $($job.id)"
