# Skvoznaya proverka zhalob i svodki ploshchadki (TZ 4.1, p.1 i 6) na nastoyashchey baze:
# zhaloba -> ochered moderacii -> reshenie -> snyatie zadaniya -> dashboard.
#
# Fayl v UTF-8 s BOM: v nem est russkiy tekst zhalob i kommentariev.

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

# Telefon moderatora zadan v services-up.ps1 (MODERATOR_PHONES).
$moder  = Login '+37490000001'
$client = Login (NewPhone)
$owner  = Login (NewPhone)

Write-Output "`n--- 1. Publikuem zadanie ---"
$cat = (Invoke-RestMethod "$base/v1/categories?kind=work").items | Select-Object -First 1
$d = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{
        categoryId = $cat.id
        title = 'Vyvoz gruntа dlya proverki zhalob'
        description = 'Zadanie, na kotorom proveryaem zhaloby na kontent i svodku ploshchadki.'
        geo = @{ lat = 40.1872; lng = 44.5152 }
        address = 'Erevan, Arabkir'
        budgetAmount = 70000
        mode = 'fixed'
    } | ConvertTo-Json)
$job = Invoke-RestMethod "$base/v1/jobs/$($d.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
Check ($job.status -ne 'draft') "zadanie opublikovano: $($job.status)"

Write-Output "`n--- 2. Korotkaya zhaloba ne prinimaetsya ---"
try {
    Invoke-RestMethod "$base/v1/complaints" -Method Post -Headers (Hdr $owner.accessToken) `
        -ContentType 'application/json; charset=utf-8' `
        -Body (@{ targetKind = 'job'; targetId = $job.id; reason = 'обман' } | ConvertTo-Json) | Out-Null
    Check $false 'po slovu "obman" smotret nechego'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 400) 'korotkaya zhaloba otklonena (400)'
}

Write-Output "`n--- 3. Na svoyo zadanie zhalovatsya nelzya ---"
try {
    Invoke-RestMethod "$base/v1/complaints" -Method Post -Headers (Hdr $client.accessToken) `
        -ContentType 'application/json; charset=utf-8' `
        -Body (@{ targetKind = 'job'; targetId = $job.id
                  reason = 'Что-то мне не нравится это задание' } | ConvertTo-Json) | Out-Null
    Check $false 'eto sobstvennyy kontent avtora'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 400) 'zhaloba na svoyo otklonena (400)'
}

Write-Output "`n--- 4. Zhaloba prinyata ---"
$c = Invoke-RestMethod "$base/v1/complaints" -Method Post -Headers (Hdr $owner.accessToken) `
    -ContentType 'application/json; charset=utf-8' `
    -Body (@{ targetKind = 'job'; targetId = $job.id
              reason = 'Просят предоплату на карту до выезда техники' } | ConvertTo-Json)
Check ($c.status -eq 'open') "zhaloba zhdet moderacii: $($c.status)"

Write-Output "`n--- 5. Povtornaya zhaloba ot togo zhe cheloveka otklonena ---"
try {
    Invoke-RestMethod "$base/v1/complaints" -Method Post -Headers (Hdr $owner.accessToken) `
        -ContentType 'application/json; charset=utf-8' `
        -Body (@{ targetKind = 'job'; targetId = $job.id
                  reason = 'И телефон в описании чужой, я звонил' } | ConvertTo-Json) | Out-Null
    Check $false 'povtornye zhaloby razduvayut ochered'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 409) 'povtornaya zhaloba otklonena (409)'
}

Write-Output "`n--- 6. Ochered moderacii ---"
$queue = Invoke-RestMethod "$base/v1/moderation/complaints" -Headers (Bearer $moder.accessToken)
$row = $queue.items | Where-Object { $_.id -eq $c.id }
Check ($null -ne $row) 'zhaloba v ocheredi'
Check ($row.targetKind -eq 'job') "vidno, na chto zhaluyutsya: $($row.targetKind)"
Check ($row.route -eq "/jobs/$($job.id)") "est ssylka na spornyy kontent: $($row.route)"
Check ($row.sameTarget -ge 1) "schetchik zhalob na obekt: $($row.sameTarget)"

try {
    Invoke-RestMethod "$base/v1/moderation/complaints" -Headers (Bearer $client.accessToken) | Out-Null
    Check $false 'ochered dostupna tolko moderacii'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 403) 'bez roli ochered zakryta (403)'
}

Write-Output "`n--- 7. Reshenie: snyat zadanie ---"
$reviewed = Invoke-RestMethod "$base/v1/moderation/complaints/$($c.id)/review" -Method Post `
    -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
    -Body (@{ action = 'removed'
              note = 'Предоплата на карту до выезда — запрещённая схема' } | ConvertTo-Json)
Check ($reviewed.status -eq 'reviewed') "zhaloba razobrana: $($reviewed.status)"
Check ($reviewed.action -eq 'removed') "deystvie: $($reviewed.action)"

$jobAfter = Invoke-RestMethod "$base/v1/jobs/$($job.id)"
Check ($jobAfter.status -eq 'cancelled') "snyatoe zadanie ushlo iz lenty: $($jobAfter.status)"

Write-Output "`n--- 8. Obe storony uznali o reshenii ---"
Start-Sleep -Milliseconds 700
$authorFeed = Invoke-RestMethod "$base/v1/notifications" -Headers (Bearer $owner.accessToken)
$clientFeed = Invoke-RestMethod "$base/v1/notifications" -Headers (Bearer $client.accessToken)
Check (@($authorFeed.items).Count -ge 1) 'pozhalovavshiysya poluchil otvet'
Check (@($clientFeed.items | Where-Object { $_.data.jobId -eq $job.id }).Count -ge 1) 'avtor zadaniya uznal, pochemu ono ischezlo'

Write-Output "`n--- 9. Razobrannaya zhaloba ne peresmatrivaetsya ---"
try {
    Invoke-RestMethod "$base/v1/moderation/complaints/$($c.id)/review" -Method Post `
        -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
        -Body (@{ action = 'dismissed'; note = 'Передумали' } | ConvertTo-Json) | Out-Null
    Check $false 'reshenie okonchatelno'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 409) 'povtornyy razbor otklonen (409)'
}

Write-Output "`n--- 10. Svodka ploshchadki ---"
$dash = Invoke-RestMethod "$base/v1/moderation/dashboard?days=30" -Headers (Bearer $moder.accessToken)
Check ($dash.jobs -ge 1) "zadaniya za period: $($dash.jobs)"
Check ($dash.users -ge 2) "registracii za period: $($dash.users)"
Check ($null -ne $dash.conversion) "konversiya zadanie->sdelka: $($dash.conversion)%"
Check ($null -ne $dash.prev) 'est sravnenie s proshlym periodom'

try {
    Invoke-RestMethod "$base/v1/moderation/dashboard" -Headers (Bearer $client.accessToken) | Out-Null
    Check $false 'svodka dostupna tolko moderacii'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 403) 'bez roli svodka zakryta (403)'
}

Write-Output "`n--- 11. Zhaloba na cheloveka ---"
$cu = Invoke-RestMethod "$base/v1/complaints" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json; charset=utf-8' `
    -Body (@{ targetKind = 'user'; targetId = $owner.user.id
              reason = 'Не выходит на связь после договорённости' } | ConvertTo-Json)
Check ($cu.targetKind -eq 'user') "zhaloba na cheloveka prinyata: $($cu.targetKind)"

$queue2 = Invoke-RestMethod "$base/v1/moderation/complaints" -Headers (Bearer $moder.accessToken)
$rowU = $queue2.items | Where-Object { $_.id -eq $cu.id }
Check ($rowU.route -eq "/users/$($owner.user.id)") "ssylka na profil: $($rowU.route)"

Invoke-RestMethod "$base/v1/moderation/complaints/$($cu.id)/review" -Method Post `
    -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
    -Body (@{ action = 'warned'; note = 'Отвечайте на сообщения после договорённости' } | ConvertTo-Json) | Out-Null

Write-Output "`n--- 12. V baze ---"
$row = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT status, action FROM orders.complaints WHERE id='$($c.id)'"
Check ($row -match 'reviewed\|removed') "zapis v baze: $row"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: ZHALOBY I SVODKA RABOTAYUT'; exit 0 }
