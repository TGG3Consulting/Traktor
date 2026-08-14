# Sborka i vykladka veb-prilozheniya. Odna komanda na vsyu vykladku.
#
# Pochemu ne prosto "flutter build": Flutter sobiraet main.dart.js i
# flutter_bootstrap.js s postoyannymi imenami. Brauzer, odnazhdy sohraniv fayl,
# mozhet otdavat staruyu kopiyu i posle vykladki. Poetomu:
#   1) v flutter_bootstrap.js podstavlyaem k main.dart.js metku sborki
#      (main.dart.js?b=20260814-2350) - dlya brauzera eto drugoy fayl;
#   2) tochku vhoda i assets razdacha otdaet s zapretom na hranenie
#      (sm. infra/local/nginx-web.conf);
#   3) canvaskit lezhit v papke s versiey - ego kesh bezopasen.
# Tak lyubaya vykladka doezzhaet do polzovatelya srazu, bez novyh adresov.
#
# VNIMANIE: tolko latinitsa - PowerShell 5.1 chitaet .ps1 v ANSI.

$ErrorActionPreference = 'Continue'
$parts = @(
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User'),
    (Join-Path $env:USERPROFILE 'sdk\flutter\bin')
) -join ';'
$env:PATH = ($parts -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'

$flutter = Join-Path $env:USERPROFILE 'sdk\flutter\bin\flutter.bat'
$web     = 'C:\Traktor\apps\mobile\build\web'
$stamp   = Get-Date -Format 'yyyyMMdd-HHmm'

Write-Output "--- 1. Sborka ($stamp) ---"
Push-Location 'C:\Traktor\apps\mobile'
& $flutter build web --pwa-strategy=none `
    --dart-define=REAL_BACKEND=true `
    --dart-define=API_BASE_URL=https://api.homly.am/v1 2>&1 |
    Select-Object -Last 3 | ForEach-Object { "  $_" }
Pop-Location
if (-not (Test-Path "$web\main.dart.js")) { Write-Output '  PROVAL: sborka ne poluchilas'; exit 1 }

Write-Output '--- 2. Metka sborki v ssylke na kod ---'
$b = Get-Content "$web\flutter_bootstrap.js" -Raw
$b = $b -replace '"mainJsPath":"main\.dart\.js"', "`"mainJsPath`":`"main.dart.js?b=$stamp`""
$b = $b -replace 'm\("main\.dart\.js"\)', "m(`"main.dart.js?b=$stamp`")"
Set-Content -Path "$web\flutter_bootstrap.js" -Value $b -Encoding UTF8 -NoNewline
if ((Get-Content "$web\flutter_bootstrap.js" -Raw) -match [regex]::Escape("main.dart.js?b=$stamp")) {
    Write-Output "  OK: kod zaprashivaetsya kak main.dart.js?b=$stamp"
} else {
    Write-Output '  PROVAL: metka ne podstavilas'
}

Write-Output '--- 3. Service worker ---'
if (Test-Path "$web\flutter_service_worker.js") {
    Remove-Item "$web\flutter_service_worker.js" -Force
    Write-Output '  udalen (on tozhe derzhal staruyu kopiyu)'
} else {
    Write-Output '  OK: ego net'
}

Write-Output '--- 4. Vykladka ---'
docker restart traktor-web 2>&1 | ForEach-Object { "  $_" }
Start-Sleep -Seconds 3

Write-Output '--- 5. Zagolovki razdachi ---'
foreach ($f in 'index.html', 'flutter_bootstrap.js', 'main.dart.js') {
    try {
        $r = Invoke-WebRequest "http://localhost:18090/$f" -Method Head -UseBasicParsing -TimeoutSec 10
        $cc = $r.Headers['Cache-Control']
        if ($cc -match 'no-store') { Write-Output "  OK: $f -> $cc" }
        else { Write-Output "  PROVAL: $f -> $cc (dolzhno byt no-store)" }
    } catch { Write-Output "  PROVAL: $f - $_" }
}

Write-Output '--- 6. Proverka snaruzhi ---'
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Traktor\scripts\live-check.ps1
