# Traktor: ustanovka Go SDK bez prav administratora (raspakovka zip v profil polzovatelya)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sdkRoot   = Join-Path $env:USERPROFILE 'sdk'
$goRoot    = Join-Path $sdkRoot 'go'
$downloads = 'C:\Traktor\scripts\_out\_dl'

Write-Output "=== USTANOVKA GO ==="
Write-Output "vremya: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')"

if (Test-Path (Join-Path $goRoot 'bin\go.exe')) {
    Write-Output "Go uzhe raspakovan v $goRoot"
} else {
    New-Item -ItemType Directory -Force -Path $sdkRoot, $downloads | Out-Null

    Write-Output "1) Zapros spiska versiy s go.dev ..."
    $releases = Invoke-RestMethod -Uri 'https://go.dev/dl/?mode=json' -TimeoutSec 60
    $stable = $releases | Where-Object { $_.stable -eq $true } | Select-Object -First 1
    $file = $stable.files | Where-Object { $_.os -eq 'windows' -and $_.arch -eq 'amd64' -and $_.kind -eq 'archive' } | Select-Object -First 1
    if (-not $file) { throw 'Ne nayden windows/amd64 zip-arhiv Go' }
    Write-Output "   versiya: $($stable.version), fayl: $($file.filename), razmer: $([math]::Round($file.size/1MB,1)) MB"

    $zipPath = Join-Path $downloads $file.filename
    if (-not (Test-Path $zipPath)) {
        Write-Output "2) Skachivanie ..."
        $sw = [Diagnostics.Stopwatch]::StartNew()
        Invoke-WebRequest -Uri "https://go.dev/dl/$($file.filename)" -OutFile $zipPath -UseBasicParsing -TimeoutSec 1800
        $sw.Stop()
        Write-Output "   skachano za $([math]::Round($sw.Elapsed.TotalSeconds,1)) sek"
    } else {
        Write-Output "2) Arhiv uzhe skachan: $zipPath"
    }

    Write-Output "3) Proverka SHA256 ..."
    $hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne $file.sha256.ToLower()) {
        Remove-Item $zipPath -Force
        throw "SHA256 ne sovpadaet! ozhidalos $($file.sha256), polucheno $hash"
    }
    Write-Output "   SHA256 OK"

    Write-Output "4) Raspakovka v $sdkRoot ..."
    Expand-Archive -Path $zipPath -DestinationPath $sdkRoot -Force
    Write-Output "   gotovo"
}

Write-Output "5) Proverka:"
& (Join-Path $goRoot 'bin\go.exe') version
& (Join-Path $goRoot 'bin\go.exe') env GOROOT GOPATH GOMODCACHE

Write-Output "6) Dobavlenie v PATH polzovatelya (bez prav administratora, obratimo) ..."
$binPath  = Join-Path $goRoot 'bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($null -eq $userPath) { $userPath = '' }
if ($userPath -split ';' -notcontains $binPath) {
    $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $binPath } else { $userPath.TrimEnd(';') + ';' + $binPath }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Output "   dobavleno: $binPath"
} else {
    Write-Output "   uzhe v PATH: $binPath"
}

# GOPATH\bin tozhe polezen (tam okazhutsya ustanovlennye utility, naprimer migrate)
$goPathBin = Join-Path $env:USERPROFILE 'go\bin'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -split ';' -notcontains $goPathBin) {
    [Environment]::SetEnvironmentVariable('Path', $userPath.TrimEnd(';') + ';' + $goPathBin, 'User')
    Write-Output "   dobavleno: $goPathBin"
}

Write-Output "=== GOTOVO ==="
