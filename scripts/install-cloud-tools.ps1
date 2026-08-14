# Traktor: ustanovka Terraform i Google Cloud CLI bez prav administratora.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sdkRoot   = Join-Path $env:USERPROFILE 'sdk'
$downloads = 'C:\Traktor\scripts\_out\_dl'
New-Item -ItemType Directory -Force -Path $sdkRoot, $downloads | Out-Null

function Add-UserPath($p) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $userPath) { $userPath = '' }
    if ($userPath -split ';' -notcontains $p) {
        [Environment]::SetEnvironmentVariable('Path', $userPath.TrimEnd(';') + ';' + $p, 'User')
        Write-Output "   PATH += $p"
    } else {
        Write-Output "   uzhe v PATH: $p"
    }
}

Write-Output "=== USTANOVKA OBLACHNYH INSTRUMENTOV ==="
Write-Output "start: $(Get-Date -Format 'HH:mm:ss')"

# ---------- Terraform ----------
$tfDir = Join-Path $sdkRoot 'terraform'
if (Test-Path (Join-Path $tfDir 'terraform.exe')) {
    Write-Output "1) Terraform uzhe ustanovlen"
} else {
    Write-Output '1) Terraform: uznaem posledniyu versiyu ...'
    $meta = Invoke-RestMethod -Uri 'https://api.releases.hashicorp.com/v1/releases/terraform/latest' -TimeoutSec 60
    $ver  = $meta.version
    $url  = "https://releases.hashicorp.com/terraform/$ver/terraform_${ver}_windows_amd64.zip"
    $zip  = Join-Path $downloads "terraform_$ver.zip"
    Write-Output "   versiya $ver, skachivanie ..."
    (New-Object System.Net.WebClient).DownloadFile($url, $zip)
    New-Item -ItemType Directory -Force -Path $tfDir | Out-Null
    & "$env:SystemRoot\System32\tar.exe" -xf $zip -C $tfDir
    Write-Output '   raspakovano'
}
Add-UserPath $tfDir

# ---------- Google Cloud CLI ----------
$gcDir = Join-Path $sdkRoot 'google-cloud-sdk'
if (Test-Path (Join-Path $gcDir 'bin\gcloud.cmd')) {
    Write-Output '2) Google Cloud CLI uzhe ustanovlen'
} else {
    Write-Output '2) Google Cloud CLI: skachivanie (~150 MB) ...'
    $url = 'https://dl.google.com/dl/cloudsdk/channels/rapid/google-cloud-cli-windows-x86_64-bundled-python.zip'
    $zip = Join-Path $downloads 'google-cloud-cli.zip'
    if (-not (Test-Path $zip)) { (New-Object System.Net.WebClient).DownloadFile($url, $zip) }
    Write-Output '   raspakovka ...'
    & "$env:SystemRoot\System32\tar.exe" -xf $zip -C $sdkRoot
    Write-Output '   gotovo'
}
Add-UserPath (Join-Path $gcDir 'bin')

Write-Output '3) Proverka:'
& (Join-Path $tfDir 'terraform.exe') version
& (Join-Path $gcDir 'bin\gcloud.cmd') --version

Write-Output "=== GOTOVO $(Get-Date -Format 'HH:mm:ss') ==="
