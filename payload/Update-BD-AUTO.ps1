[CmdletBinding()]
param(
  [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework

$appRoot = Split-Path -Parent $PSCommandPath
$versionPath = Join-Path $appRoot 'VERSION'
$currentVersion = if (Test-Path -LiteralPath $versionPath) {
  (Get-Content -LiteralPath $versionPath -Raw).Trim()
} else {
  '0.0.0'
}

function Show-InfoMessage([string]$Message, [string]$Title = 'BD-AUTO Updater') {
  if (-not $Quiet) {
    [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Information') | Out-Null
  }
}

function Show-ErrorMessage([string]$Message, [string]$Title = 'BD-AUTO Updater') {
  [System.Windows.MessageBox]::Show($Message, $Title, 'OK', 'Error') | Out-Null
}

function Get-LatestRelease {
  $headers = @{
    Accept = 'application/vnd.github+json'
    'User-Agent' = 'BD-AUTO-Updater'
  }
  Invoke-RestMethod -Uri 'https://api.github.com/repos/Drakcain/BD-AUTO/releases/latest' -Headers $headers
}

function Get-NormalizedVersion([string]$Value) {
  try {
    return [version]($Value.Trim().TrimStart('v'))
  } catch {
    return [version]'0.0.0'
  }
}

try {
  $release = Get-LatestRelease
  $latestTag = [string]$release.tag_name
  $latestVersion = $latestTag.TrimStart('v')

  if ((Get-NormalizedVersion $latestVersion) -le (Get-NormalizedVersion $currentVersion)) {
    Show-InfoMessage "BD-AUTO is already up to date.`n`nCurrent version: v$currentVersion"
    exit 0
  }

  $installer = $release.assets | Where-Object name -eq 'BD-AUTO-Setup.exe' | Select-Object -First 1
  $checksum = $release.assets | Where-Object name -eq 'BD-AUTO-Setup.exe.sha256' | Select-Object -First 1
  if (-not $installer) {
    throw 'The latest GitHub release does not include BD-AUTO-Setup.exe.'
  }

  $message = "A new BD-AUTO update is available.`n`nInstalled: v$currentVersion`nLatest: v$latestVersion`n`nDownload and launch the installer now?"
  if (-not $Quiet) {
    $result = [System.Windows.MessageBox]::Show($message, 'BD-AUTO Update Available', 'YesNo', 'Information')
    if ($result -ne 'Yes') {
      exit 0
    }
  }

  $tempDir = Join-Path $env:TEMP ("bd-auto-update-{0}" -f [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
  $installerPath = Join-Path $tempDir 'BD-AUTO-Setup.exe'

  Invoke-WebRequest -Uri $installer.browser_download_url -OutFile $installerPath -Headers @{ 'User-Agent' = 'BD-AUTO-Updater' }

  if ($checksum) {
    $checksumPath = Join-Path $tempDir 'BD-AUTO-Setup.exe.sha256'
    Invoke-WebRequest -Uri $checksum.browser_download_url -OutFile $checksumPath -Headers @{ 'User-Agent' = 'BD-AUTO-Updater' }
    $checksumText = (Get-Content -LiteralPath $checksumPath -Raw).Trim()
    $expectedHash = ($checksumText -split '\s+')[0].Trim().ToUpperInvariant()
    $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($expectedHash -ne $actualHash) {
      throw "Installer checksum mismatch. Expected $expectedHash, got $actualHash."
    }
  }

  Start-Process -FilePath $installerPath -Verb RunAs
  Show-InfoMessage "Downloaded and launched BD-AUTO v$latestVersion.`n`nFollow the installer prompts to finish the update."
} catch {
  Show-ErrorMessage $_.Exception.Message
  exit 1
}
