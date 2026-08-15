# Uborka stenda: ubiraet iz lenty vsyo, chto nasozdavali skvoznye proverki.
#
# Proverki rabotayut na nastoyashchey baze - inache oni nichego ne dokazyvayut.
# Pobochnyy effekt: za noch v lente kopyatsya desyatki zadaniy vrode
# "Zadanie dlya proverki chata", i demonstraciya vyglyadit kak svalka.
#
# Chto delaet: otmenyaet zadaniya vseh, krome demo-akkauntov (+37490000001/2)
# i tekushchego vladeltsa stenda. Nichego ne udalyaet: sdelki, otzyvy i chaty
# ostayutsya v baze - na nih ssylayutsya proverki i istoriya.
#
# VNIMANIE: tolko dlya stenda. V boyu zapuskat nelzya.

$ErrorActionPreference = 'Continue'
$base = 'http://127.0.0.1:18080'

function Login($phone) {
    Invoke-RestMethod "$base/v1/auth/otp/start" -Method Post -ContentType 'application/json; charset=utf-8' `
        -Body (@{ phone = $phone } | ConvertTo-Json) | Out-Null
    return Invoke-RestMethod "$base/v1/auth/otp/verify" -Method Post -ContentType 'application/json; charset=utf-8' `
        -Headers @{ 'Idempotency-Key' = [guid]::NewGuid().ToString() } `
        -Body (@{ phone = $phone; code = '000000' } | ConvertTo-Json)
}
function Psql($sql) {
    return (docker exec traktor-postgres psql -U traktor -d traktor -t -A -c $sql)
}

Write-Output '--- 1. Demo-akkaunty ---'
$keep = @()
foreach ($phone in @('+37490000001', '+37490000002')) {
    $s = Login $phone
    $keep += $s.user.id
    Write-Output "  $phone -> $($s.user.id)"
}
$list = ($keep | ForEach-Object { "'$_'" }) -join ','

Write-Output "`n--- 2. Skolko zadaniy v lente seychas ---"
$before = Psql "SELECT count(*) FROM orders.jobs WHERE status IN ('published','collecting_offers','bidding')"
Write-Output "  $before"

Write-Output "`n--- 3. Ubiraem chuzhie testovye zadaniya ---"
# Sdelki i otzyvy ne trogaem: oni zhivut svoey zhiznyu i v lente ne vidny.
Psql "UPDATE orders.jobs SET status = 'cancelled', updated_at = now()
      WHERE status IN ('published','collecting_offers','bidding','deciding','deal_pending')
        AND client_id::text NOT IN ($list)" | ForEach-Object { "  $_" }

Write-Output "`n--- 4. Skrytye testovye kategorii ---"
Psql "UPDATE catalog.categories SET active = false WHERE slug LIKE 'work-check-%'" | ForEach-Object { "  $_" }

Write-Output "`n--- 5. Chto ostalos v lente ---"
$after = Psql "SELECT count(*) FROM orders.jobs WHERE status IN ('published','collecting_offers','bidding')"
Write-Output "  $after"
Psql "SELECT title FROM orders.jobs WHERE status IN ('published','collecting_offers','bidding') ORDER BY created_at DESC LIMIT 10" |
    ForEach-Object { "  $_" }

Write-Output "`n=================================="
Write-Output 'ITOG: STEND UBRAN'
