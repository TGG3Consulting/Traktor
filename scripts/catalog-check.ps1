# Skvoznaya proverka pravki spravochnika (TZ 4.1, p.5) na nastoyashchey baze:
# sozdanie kategorii -> ona srazu v vizarde -> pravka -> skrytie -> vozvrat.
#
# Fayl v UTF-8 s BOM: v nem est russkie nazvaniya kategoriy.

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

$moder  = Login '+37490000001'
$client = Login (NewPhone)
$slug = 'work-check-' + (Get-Random -Minimum 100000 -Maximum 999999)

Write-Output "`n--- 1. Bez roli spravochnik ne pravitsya ---"
try {
    Invoke-RestMethod "$base/v1/moderation/categories" -Headers (Bearer $client.accessToken) | Out-Null
    Check $false 'razdel dostupen tolko moderacii'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 403) 'bez roli razdel zakryt (403)'
}

Write-Output "`n--- 2. Kriteriy nazvaniya: nuzhny vse tri yazyka ---"
try {
    Invoke-RestMethod "$base/v1/moderation/categories" -Method Post -Headers (Hdr $moder.accessToken) `
        -ContentType 'application/json; charset=utf-8' -Body (@{
            kind = 'work'; slug = $slug
            name = @{ ru = 'Бурение скважин'; en = 'Well drilling' }
        } | ConvertTo-Json)  | Out-Null
    Check $false 'nedoperevod ne dolzhen prohodit'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 400) 'nazvanie bez armyanskogo otkloneno (400)'
}

Write-Output "`n--- 3. Klyuch tolko latinicey ---"
try {
    Invoke-RestMethod "$base/v1/moderation/categories" -Method Post -Headers (Hdr $moder.accessToken) `
        -ContentType 'application/json; charset=utf-8' -Body (@{
            kind = 'work'; slug = 'Бурение'
            name = @{ ru = 'Бурение'; hy = 'Հորատում'; en = 'Drilling' }
        } | ConvertTo-Json) | Out-Null
    Check $false 'klyuch dolzhen byt latinicey'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 400) 'kirillicheskiy klyuch otklonen (400)'
}

Write-Output "`n--- 4. Novaya kategoriya ---"
$created = Invoke-RestMethod "$base/v1/moderation/categories" -Method Post -Headers (Hdr $moder.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{
        kind = 'work'; slug = $slug
        name = @{ ru = 'Бурение скважин'; hy = 'Հորատում'; en = 'Well drilling' }
        icon = 'pickaxe'; sortOrder = 40
        specTemplate = @(
            @{ key = 'depth'; type = 'number'; unit = 'м'; label_ru = 'Глубина' }
            @{ key = 'soil'; type = 'select'; label_ru = 'Грунт'; options = @('мягкий', 'скальный') }
        )
    } | ConvertTo-Json -Depth 5)
Check ($created.id -ne '') "kategoriya sozdana: $($created.id)"
Check ($created.specTemplate.Count -eq 2) "shablon harakteristik sohranen: $($created.specTemplate.Count)"

Write-Output "`n--- 5. Ona srazu vidna v vizarde, bez vykata ---"
$public = Invoke-RestMethod "$base/v1/categories?kind=work"
$row = $public.items | Where-Object { $_.id -eq $created.id }
Check ($null -ne $row) 'novaya kategoriya v obshchem spravochnike'
Check ($row.specTemplate.Count -eq 2) 'polya harakteristik prishli klientu'

Write-Output "`n--- 6. Povtornyy klyuch ne prohodit ---"
try {
    Invoke-RestMethod "$base/v1/moderation/categories" -Method Post -Headers (Hdr $moder.accessToken) `
        -ContentType 'application/json; charset=utf-8' -Body (@{
            kind = 'work'; slug = $slug
            name = @{ ru = 'Ещё бурение'; hy = 'Հորատում 2'; en = 'Drilling 2' }
        } | ConvertTo-Json) | Out-Null
    Check $false 'klyuch unikalen'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 409) 'zanyatyy klyuch otklonen (409)'
}

Write-Output "`n--- 7. Slomannoe pole harakteristik ne prohodit ---"
try {
    Invoke-RestMethod "$base/v1/moderation/categories/$($created.id)" -Method Patch `
        -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' -Body (@{
            name = @{ ru = 'Бурение скважин'; hy = 'Հորատում'; en = 'Well drilling' }
            specTemplate = @(@{ key = 'soil'; type = 'select'; label_ru = 'Грунт' })
        } | ConvertTo-Json -Depth 5) | Out-Null
    Check $false 'spisok bez variantov nechem zapolnit'
} catch {
    Check ($_.Exception.Response.StatusCode.value__ -eq 400) 'spisok bez variantov otklonen (400)'
}

Write-Output "`n--- 8. Pravka nazvaniya i poryadka ---"
$updated = Invoke-RestMethod "$base/v1/moderation/categories/$($created.id)" -Method Patch `
    -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' -Body (@{
        name = @{ ru = 'Бурение и скважины'; hy = 'Հորատում'; en = 'Drilling and wells' }
        icon = 'pickaxe'; sortOrder = 15
        specTemplate = @(@{ key = 'depth'; type = 'number'; unit = 'м'; label_ru = 'Глубина' })
    } | ConvertTo-Json -Depth 5)
Check ($updated.sortOrder -eq 15) "poryadok obnovlen: $($updated.sortOrder)"
Check ($updated.specTemplate.Count -eq 1) "shablon obnovlen: $($updated.specTemplate.Count)"
Check ($updated.slug -eq $slug) "klyuch ne menyaetsya: $($updated.slug)"

Write-Output "`n--- 9. Skrytie ubiraet iz vizarda ---"
Invoke-RestMethod "$base/v1/moderation/categories/$($created.id)/visibility" -Method Post `
    -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
    -Body (@{ active = $false } | ConvertTo-Json) | Out-Null
$public2 = Invoke-RestMethod "$base/v1/categories?kind=work"
Check (@($public2.items | Where-Object { $_.id -eq $created.id }).Count -eq 0) 'skrytaya kategoriya ushla iz vizarda'

$all = Invoke-RestMethod "$base/v1/moderation/categories?kind=work" -Headers (Bearer $moder.accessToken)
$hidden = $all.items | Where-Object { $_.id -eq $created.id }
Check ($null -ne $hidden) 'moderator vidit skrytuyu: inache vernut ee nevozmozhno'
Check ($hidden.active -eq $false) "priznak vidimosti: $($hidden.active)"

Write-Output "`n--- 10. Vozvrat ---"
Invoke-RestMethod "$base/v1/moderation/categories/$($created.id)/visibility" -Method Post `
    -Headers (Hdr $moder.accessToken) -ContentType 'application/json; charset=utf-8' `
    -Body (@{ active = $true } | ConvertTo-Json) | Out-Null
$public3 = Invoke-RestMethod "$base/v1/categories?kind=work"
Check (@($public3.items | Where-Object { $_.id -eq $created.id }).Count -eq 1) 'kategoriya vernulas v vizard'

Write-Output "`n--- 11. Zadanie v novoy kategorii sozdaetsya ---"
$d = Invoke-RestMethod "$base/v1/jobs/drafts" -Method Post -Headers (Hdr $client.accessToken) `
    -ContentType 'application/json; charset=utf-8' -Body (@{
        categoryId = $created.id
        title = 'Burenie skvazhiny 30 m'
        description = 'Zadanie v kategorii, sozdannoy moderaciey bez vykata servisa.'
        geo = @{ lat = 40.1872; lng = 44.5152 }
        address = 'Erevan, Davtashen'
        budgetAmount = 150000
        mode = 'fixed'
    } | ConvertTo-Json)
$job = Invoke-RestMethod "$base/v1/jobs/$($d.id)/publish" -Method Post -Headers (Hdr $client.accessToken)
Check ($job.categoryId -eq $created.id) 'zadanie ssylaetsya na novuyu kategoriyu'

Write-Output "`n--- 12. V baze ---"
$row = docker exec traktor-postgres psql -U traktor -d traktor -t -A -c `
    "SELECT slug, active FROM catalog.categories WHERE id='$($created.id)'"
Check ($row -match "$slug\|t") "zapis v baze: $row"

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: SPRAVOCHNIK PRAVITSYA BEZ VYKATA'; exit 0 }
