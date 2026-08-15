# Gotovit auktsion dlya ruchnoy proverki zhivyh stavok:
# zakazchik +37490000001 publikuet torg, ispolnitel +37490000002 uzhe postavil.
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

$client = Login '+37490000001'
$owner  = Login '+37490000002'
$cat = (Invoke-RestMethod "$base/v1/categories?kind=work").items | Select-Object -First 1
$d = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json' -Body (@{
        categoryId = $cat.id
        title = 'Zhivoy torg: vspashka 2 ga'
        description = 'Proveryaem, chto stavki prihodyat na ekran srazu, bez obnovleniya.'
        geo = @{ lat = 40.1872; lng = 44.5152 }
        address = 'Erevan, Avan'
        budgetAmount = 200000
        mode = 'auction'
        auction = @{ durationH = 24; decisionWindowH = 12 }
    } | ConvertTo-Json)
$job = Invoke-RestMethod "$base/v1/jobs/$($d.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
Invoke-RestMethod "$base/v1/jobs/$($job.id)/bids" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json' -Body (@{ price = 180000 } | ConvertTo-Json) | Out-Null

Write-Output "TORG: /jobs/$($job.id)/bids"
Write-Output $job.id
