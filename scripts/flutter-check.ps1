# Analiz i testy Flutter-paketov proekta.
# Ispolzovanie: flutter-check.ps1            - vse pakety
#               flutter-check.ps1 api_client - odin paket
#
# VNIMANIE: tolko latinitsa - PowerShell 5.1 chitaet .ps1 v ANSI.

param([string]$only = '')

$ErrorActionPreference = 'Continue'
$parts = @(
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User'),
    (Join-Path $env:USERPROFILE 'sdk\flutter\bin')
) -join ';'
$env:PATH = ($parts -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'

$flutter = Join-Path $env:USERPROFILE 'sdk\flutter\bin\flutter.bat'
$dart    = Join-Path $env:USERPROFILE 'sdk\flutter\bin\dart.bat'
$failed  = $false

$targets = @(
    @{ name = 'api_client';    path = 'C:\Traktor\packages\api_client';    pure = $true },
    @{ name = 'design_system'; path = 'C:\Traktor\packages\design_system'; pure = $false },
    @{ name = 'mobile';        path = 'C:\Traktor\apps\mobile';            pure = $false }
)
if ($only) { $targets = $targets | Where-Object { $_.name -eq $only } }

foreach ($t in $targets) {
    Write-Output "`n=== $($t.name) ==="
    Set-Location $t.path

    Write-Output '--- pub get ---'
    & $flutter pub get 2>&1 | Select-Object -Last 2 | ForEach-Object { "  $_" }

    Write-Output '--- analyze ---'
    $a = & $flutter analyze 2>&1
    $a | Select-Object -Last 6 | ForEach-Object { "  $_" }
    if ($LASTEXITCODE -ne 0) { $failed = $true; Write-Output '  PROVAL: analyze' }

    Write-Output '--- test ---'
    if ($t.pure) {
        # Chistyy Dart-paket: testy gonyaem dart test, flutter test ego ne beret.
        & $dart test 2>&1 | Select-Object -Last 8 | ForEach-Object { "  $_" }
    } else {
        & $flutter test 2>&1 | Select-Object -Last 8 | ForEach-Object { "  $_" }
    }
    if ($LASTEXITCODE -ne 0) { $failed = $true; Write-Output '  PROVAL: testy' }
}

Write-Output "`n=================================="
if ($failed) { Write-Output 'ITOG: EST PROVALY'; exit 1 } else { Write-Output 'ITOG: VSE ZELENOE'; exit 0 }
