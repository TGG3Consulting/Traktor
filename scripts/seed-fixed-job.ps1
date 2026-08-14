# Sozdaet odno opublikovannoe zadanie s fiks-tsenoy v Erevane - chtoby v lente
# bylo na chem proverit otklik glazami.
$ErrorActionPreference = 'Continue'
$base = 'http://127.0.0.1:18080'
$phone = '+37493000777'   # postoyannyy "demo-zakazchik"

Invoke-RestMethod "$base/v1/auth/otp/start" -Method Post -ContentType 'application/json' `
    -Body (@{ phone = $phone } | ConvertTo-Json) | Out-Null
$s = Invoke-RestMethod "$base/v1/auth/otp/verify" -Method Post -ContentType 'application/json' `
    -Headers @{ 'Idempotency-Key' = [guid]::NewGuid().ToString() } `
    -Body (@{ phone = $phone; code = '000000' } | ConvertTo-Json)

$h = @{ Authorization = "Bearer $($s.accessToken)"; 'Idempotency-Key' = [guid]::NewGuid().ToString() }
$cats = Invoke-RestMethod "$base/v1/categories?kind=work"
$transport = $cats.items | Where-Object { $_.slug -eq 'work-transport' } | Select-Object -First 1

$draft = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers $h -ContentType 'application/json' `
    -Body (@{
        categoryId   = $transport.id
        title        = 'Vyvezti 12 t stroitelnogo musora'
        description  = 'Boy kirpicha i shtukaturka posle demontazha, pogruzka moya, vyvoz na poligon.'
        geo          = @{ lat = 40.1950; lng = 44.5100 }
        address      = 'Erevan, Arabkir'
        access       = 'yes'
        budgetAmount = 45000
        mode         = 'fixed'
        draftStep    = 5
    } | ConvertTo-Json)

$h2 = @{ Authorization = "Bearer $($s.accessToken)"; 'Idempotency-Key' = [guid]::NewGuid().ToString() }
$job = Invoke-RestMethod "$base/v1/jobs/$($draft.id)/publish" -Method Post -Headers $h2
Write-Output "zadanie: $($job.id) status: $($job.status) tsena: $($job.budgetAmount)"
