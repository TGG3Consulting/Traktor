# Proverka, chto kompyuter deystvitelno otdaet servisy naruzhu cherez homly.am.
#
# Vazhno pro DNS: domashniy router keshiruet staryy adres homly.am (hosting
# name.am), poetomu s etogo kompyutera imya vedet ne v Cloudflare i TLS rvetsya.
# Snaruzhi (s telefona, iz interneta) vsyo otkryvaetsya normalno. Chtoby proverka
# merila realnuyu dostupnost, a ne kesh routera, adres beryom u 1.1.1.1 i
# podstavlyaem yavno cherez curl --resolve.

$failed = $false
function Check($cond, $msg) {
    if ($cond) { Write-Output "  OK: $msg" } else { Write-Output "  PROVAL: $msg"; $script:failed = $true }
}

# Adres Cloudflare dlya nashego domena
$ip = $null
try {
    $ip = (Resolve-DnsName -Name 'app.homly.am' -Type A -Server '1.1.1.1' -ErrorAction Stop |
           Where-Object { $_.IPAddress } | Select-Object -First 1).IPAddress
} catch { }
if (-not $ip) { $ip = '104.21.39.15' }
Write-Output "`n--- Proverka vneshnih adresov (cherez $ip) ---"

function Fetch($hostname, $path, $extra) {
    $a = @('-s', '--max-time', '25', '--resolve', "${hostname}:443:$ip") + $extra + @("https://$hostname$path")
    return (& curl.exe @a) 2>&1
}

# 1. Shlyuz otvechaet
$code = Fetch 'api.homly.am' '/healthz' @('-o', 'NUL', '-w', '%{http_code}')
Check ($code -eq '200') "api.homly.am/healthz -> $code"

# 2. Polnyy vhod snaruzhi: kod 000000
$phone = '+3749' + (Get-Random -Minimum 1000000 -Maximum 9999999)
Fetch 'api.homly.am' '/v1/auth/otp/start' @('-o', 'NUL', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', "{\`"phone\`":\`"$phone\`"}") | Out-Null
$body = Fetch 'api.homly.am' '/v1/auth/otp/verify' @('-X', 'POST', '-H', 'Content-Type: application/json',
        '-H', "Idempotency-Key: live-$([guid]::NewGuid())", '-d', "{\`"phone\`":\`"$phone\`",\`"code\`":\`"000000\`"}")
$json = $null
try { $json = $body | ConvertFrom-Json } catch { }
Check ($json -and $json.accessToken -and $json.user.id) "vhod snaruzhi po kodu 000000 (otvet: $($body -replace '\s+',' ' | Select-Object -First 1))"

# 3. Veb-prilozhenie otdaetsya
$app = Fetch 'app.homly.am' '/' @()
Check ($app -match 'Traktor') 'app.homly.am otdaet prilozhenie'

# 4. Realtime
$rt = Fetch 'rt.homly.am' '/health' @('-o', 'NUL', '-w', '%{http_code}')
Check ($rt -eq '200') "rt.homly.am (realtime) -> $rt"

# 5. DNS chistyy: adresa domenov vedut tolko na tunnel Cloudflare.
#
# Ostavshayasya A-zapis parkovki lomaet sayt cherez raz - brauzer vybiraet
# lyuboy iz adresov, i chelovek popadaet na "Welcome to app.homly.am".
# Nashi proverki vyshe hodyat s yavnym ukazaniem adresa Cloudflare i etogo
# ne zamechayut, poetomu sveryaem spisok otdelno.
Write-Output "`n--- 5. DNS: tolko adresa tunnelya ---"
foreach ($name in @('api.homly.am', 'app.homly.am', 'rt.homly.am')) {
    $ips = @()
    try {
        $ips = (Resolve-DnsName -Name $name -Type A -ErrorAction Stop |
                Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress })
    } catch { }
    # Cloudflare otdaet adresa iz svoih diapazonov 104.x i 172.6x.
    $strangers = @($ips | Where-Object { $_ -notmatch '^(104\.|172\.6[4-9]\.|172\.7[0-1]\.)' })
    Check ($strangers.Count -eq 0) "$name -> $($ips -join ', ')"
    if ($strangers.Count -gt 0) {
        Write-Output "    lishnie zapisi: $($strangers -join ', ') - udalite ih v zone domena"
    }
}

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: VSE RABOTAET SNARUZHI'; exit 0 }
