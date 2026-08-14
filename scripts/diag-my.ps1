# Diagnostika: pochemu chernovik ne popadaet v "moi zadaniya".
$ErrorActionPreference = 'Continue'
$base = 'http://127.0.0.1:18080'
$p = '+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999)

Invoke-RestMethod "$base/v1/auth/otp/start" -Method Post -ContentType 'application/json' `
    -Body (@{ phone = $p } | ConvertTo-Json) | Out-Null
$s = Invoke-RestMethod "$base/v1/auth/otp/verify" -Method Post -ContentType 'application/json' `
    -Headers @{ 'Idempotency-Key' = [guid]::NewGuid().ToString() } `
    -Body (@{ phone = $p; code = '000000' } | ConvertTo-Json)

$h = @{ Authorization = "Bearer $($s.accessToken)"; 'Idempotency-Key' = [guid]::NewGuid().ToString() }
$d = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers $h -ContentType 'application/json' `
    -Body (@{ title = 'diag' } | ConvertTo-Json)
Write-Output "chernovik: $($d.id)"
Write-Output "clientId v otvete: $($d.clientId)"
Write-Output "user.id iz vhoda:  $($s.user.id)"

$raw = Invoke-WebRequest "$base/v1/jobs/my" -Headers @{ Authorization = "Bearer $($s.accessToken)" } -UseBasicParsing
Write-Output "status /v1/jobs/my: $($raw.StatusCode)"
Write-Output "telo: $($raw.Content)"

Write-Output "--- napryamuyu v servis (minuya shlyuz) ---"
$direct = Invoke-WebRequest "http://127.0.0.1:18084/v1/jobs/my" -Headers @{ 'X-User-Id' = $s.user.id } -UseBasicParsing
Write-Output "telo: $($direct.Content)"

Write-Output "--- chto v baze ---"
docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT id, client_id, status FROM orders.jobs ORDER BY created_at DESC LIMIT 3"
