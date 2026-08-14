# Traktor: ustanovka Flutter SDK bez prav administratora (raspakovka v profil).
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sdkRoot     = Join-Path $env:USERPROFILE 'sdk'
$flutterRoot = Join-Path $sdkRoot 'flutter'
$downloads   = 'C:\Traktor\scripts\_out\_dl'

Write-Output "=== USTANOVKA FLUTTER ==="
Write-Output "vremya starta: $(Get-Date -Format 'HH:mm:ss')"

if (Test-Path (Join-Path $flutterRoot 'bin\flutter.bat')) {
    Write-Output "Flutter uzhe raspakovan v $flutterRoot"
} else {
    New-Item -ItemType Directory -Force -Path $sdkRoot, $downloads | Out-Null

    Write-Output '1) Zapros spiska relizov ...'
    $feed = Invoke-RestMethod -Uri 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json' -TimeoutSec 120
    $stableHash = $feed.current_release.stable
    $rel = $feed.releases | Where-Object { $_.hash -eq $stableHash -and $_.channel -eq 'stable' } | Select-Object -First 1
    if (-not $rel) { throw 'ne nayden stabilnyy reliz Flutter' }
    Write-Output "   versiya: $($rel.version), arhiv: $($rel.archive)"

    $url  = $feed.base_url + '/' + $rel.archive
    $zip  = Join-Path $downloads (Split-Path $rel.archive -Leaf)

    if (-not (Test-Path $zip)) {
        Write-Output "2) Skachivanie (~1 GB, eto dolgo) ..."
        $sw = [Diagnostics.Stopwatch]::StartNew()
        # WebClient zametno bystree Invoke-WebRequest na bolshih faylah.
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($url, $zip)
        $sw.Stop()
        Write-Output "   skachano za $([math]::Round($sw.Elapsed.TotalMinutes,1)) min"
    } else {
        Write-Output "2) Arhiv uzhe skachan: $zip"
    }

    if ($rel.sha256) {
        Write-Output '3) Proverka SHA256 ...'
        $hash = (Get-FileHash -Path $zip -Algorithm SHA256).Hash.ToLower()
        if ($hash -ne $rel.sha256.ToLower()) {
            Remove-Item $zip -Force
            throw "SHA256 ne sovpadaet (ozhidalos $($rel.sha256))"
        }
        Write-Output '   SHA256 OK'
    } else {
        Write-Output '3) SHA256 v feede otsutstvuet - propuskaem'
    }

    Write-Output "4) Raspakovka v $sdkRoot ..."
    $sw = [Diagnostics.Stopwatch]::StartNew()
    # tar.exe (vstroen v Windows 10+) raspakovyvaet bolshie zip kuda bystree Expand-Archive.
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path $tar) {
        & $tar -xf $zip -C $sdkRoot
        if ($LASTEXITCODE -ne 0) { throw "tar vernul $LASTEXITCODE" }
    } else {
        Expand-Archive -Path $zip -DestinationPath $sdkRoot -Force
    }
    $sw.Stop()
    Write-Output "   raspakovano za $([math]::Round($sw.Elapsed.TotalMinutes,1)) min"
}

Write-Output '5) Dobavlenie v PATH polzovatelya ...'
$binPath  = Join-Path $flutterRoot 'bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($null -eq $userPath) { $userPath = '' }
if ($userPath -split ';' -notcontains $binPath) {
    [Environment]::SetEnvironmentVariable('Path', $userPath.TrimEnd(';') + ';' + $binPath, 'User')
    Write-Output "   dobavleno: $binPath"
} else {
    Write-Output "   uzhe v PATH: $binPath"
}

Write-Output '6) Proverka (pervyy zapusk dolgiy - Flutter dokachivaet Dart SDK) ...'
$env:Path = "$binPath;$env:Path"
& (Join-Path $binPath 'flutter.bat') --version
Write-Output ''
& (Join-Path $binPath 'flutter.bat') doctor -v

Write-Output "=== GOTOVO $(Get-Date -Format 'HH:mm:ss') ==="
