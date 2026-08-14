# Zapusk odnogo faila testov s polnym vyvodom.
# Ispolzovanie: test-file.ps1 <paket> <put-k-testu>
param(
    [string]$pkg = 'C:\Traktor\apps\mobile',
    [string]$file = 'test'
)

$parts = @(
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User'),
    (Join-Path $env:USERPROFILE 'sdk\flutter\bin')
) -join ';'
$env:PATH = ($parts -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'

Set-Location $pkg
& (Join-Path $env:USERPROFILE 'sdk\flutter\bin\flutter.bat') test $file 2>&1 | ForEach-Object { "$_" }
