# Polnyy vyvod flutter analyze po prilozheniyu.
$parts = @(
    [Environment]::GetEnvironmentVariable('Path', 'Machine'),
    [Environment]::GetEnvironmentVariable('Path', 'User'),
    (Join-Path $env:USERPROFILE 'sdk\flutter\bin')
) -join ';'
$env:PATH = ($parts -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'

Set-Location 'C:\Traktor\apps\mobile'
& (Join-Path $env:USERPROFILE 'sdk\flutter\bin\flutter.bat') analyze 2>&1 | ForEach-Object { "$_" }
