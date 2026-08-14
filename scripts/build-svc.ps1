# Sborka i testy odnogo servisa: go mod tidy -> gofmt -> build -> vet -> test.
# Ispolzovanie: build-svc.ps1 catalog
#
# VNIMANIE: tolko latinitsa - PowerShell 5.1 chitaet .ps1 v ANSI.

param([string]$svc = 'catalog')

$ErrorActionPreference = 'Continue'
$parts = @(
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User'),
    (Join-Path $env:USERPROFILE 'sdk\go\bin'),
    (Join-Path $env:USERPROFILE 'go\bin')
) -join ';'
$env:PATH = ($parts -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'

$go  = Join-Path $env:USERPROFILE 'sdk\go\bin\go.exe'
$dir = "C:\Traktor\services\$svc"
if (-not (Test-Path $dir)) { Write-Output "net takogo servisa: $svc"; exit 1 }
Set-Location $dir

Write-Output "=== $svc ==="
Write-Output '--- go mod tidy ---'
& $go mod tidy 2>&1 | ForEach-Object { "  $_" }

Write-Output '--- gofmt ---'
$bad = & $go fmt ./... 2>&1
if ($bad) { $bad | ForEach-Object { "  otformatirovan: $_" } } else { Write-Output '  ok' }

Write-Output '--- build ---'
& $go build ./... 2>&1 | ForEach-Object { "  $_" }
if ($LASTEXITCODE -ne 0) { Write-Output '  PROVAL: sborka'; exit 1 }
Write-Output '  ok'

Write-Output '--- vet ---'
& $go vet ./... 2>&1 | ForEach-Object { "  $_" }
if ($LASTEXITCODE -ne 0) { Write-Output '  PROVAL: vet'; exit 1 }
Write-Output '  ok'

Write-Output '--- test ---'
& $go test ./... 2>&1 | ForEach-Object { "  $_" }
if ($LASTEXITCODE -ne 0) { Write-Output '  PROVAL: testy'; exit 1 }

Write-Output "=== ${svc}: VSE ZELENOE ==="
