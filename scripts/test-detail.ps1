# Podrobnyy vyvod padayushchih testov.
# Ispolzovanie: test-detail.ps1 <put-k-paketu> [filtr]
param([string]$path = 'C:\Traktor\apps\mobile', [string]$filter = '')

$parts = @(
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User'),
    (Join-Path $env:USERPROFILE 'sdk\flutter\bin')
) -join ';'
$env:PATH = ($parts -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'

Set-Location $path
$flutter = Join-Path $env:USERPROFILE 'sdk\flutter\bin\flutter.bat'
if ($filter) {
    & $flutter test --plain-name $filter 2>&1 | ForEach-Object { "$_" }
} else {
    & $flutter test 2>&1 | ForEach-Object { "$_" }
}
