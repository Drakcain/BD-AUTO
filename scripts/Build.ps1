[CmdletBinding()]
param(
  [ValidatePattern('^\d+\.\d+\.\d+([.-][A-Za-z0-9.-]+)?$')]
  [string]$Version,
  [switch]$RefreshBdcli
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $RepoRoot 'build'
$stagedPayload = Join-Path $buildRoot 'payload'
$brandingRoot = Join-Path $buildRoot 'branding'
$versionFile = Join-Path $RepoRoot 'VERSION'

if (-not $Version) {
  if (-not (Test-Path -LiteralPath $versionFile)) {
    throw "VERSION file was not found: $versionFile"
  }
  $Version = (Get-Content -LiteralPath $versionFile -Raw).Trim()
}

function Add-VerifiedBdcliToPayload {
  param([Parameter(Mandatory = $true)][string]$PayloadRoot)

  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $repoBundledCli = Join-Path $RepoRoot 'payload\bin\bdcli.exe'
  $repoBundledMetadata = Join-Path $RepoRoot 'payload\bin\bdcli-source.json'
  $installedCli = 'C:\Tools\BD-AUTO\bin\bdcli.exe'
  $installedMetadata = 'C:\Tools\BD-AUTO\bin\bdcli-source.json'
  $tempRoot = Join-Path $env:TEMP ("bd-auto-build-{0}" -f [guid]::NewGuid().ToString('N'))
  $zipPath = "$tempRoot.zip"
  $checksumPath = "$tempRoot-checksums.txt"

  function Copy-BundledBdcli {
    param(
      [Parameter(Mandatory = $true)][string]$CliPath,
      [Parameter(Mandatory = $true)][string]$MetadataPath,
      [Parameter(Mandatory = $true)][string]$SourceLabel
    )

    $binDir = Join-Path $PayloadRoot 'bin'
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    Copy-Item -LiteralPath $CliPath -Destination (Join-Path $binDir 'bdcli.exe') -Force
    Copy-Item -LiteralPath $MetadataPath -Destination (Join-Path $binDir 'bdcli-source.json') -Force
    Write-Warning "Using bundled BetterDiscord CLI from $SourceLabel because live refresh was skipped or unavailable."
  }

  if (-not $RefreshBdcli) {
    if ((Test-Path -LiteralPath $repoBundledCli) -and (Test-Path -LiteralPath $repoBundledMetadata)) {
      Copy-BundledBdcli -CliPath $repoBundledCli -MetadataPath $repoBundledMetadata -SourceLabel 'repo payload\bin'
      return
    }

    if ((Test-Path -LiteralPath $installedCli) -and (Test-Path -LiteralPath $installedMetadata)) {
      Copy-BundledBdcli -CliPath $installedCli -MetadataPath $installedMetadata -SourceLabel 'local C:\Tools\BD-AUTO\bin cache'
      return
    }
  }

  try {
    $headers = @{ 'User-Agent' = 'BD-AUTO Build' }
    $gitHubToken = $env:BD_AUTO_GITHUB_TOKEN
    if ([string]::IsNullOrWhiteSpace($gitHubToken)) { $gitHubToken = $env:GH_TOKEN }
    if ([string]::IsNullOrWhiteSpace($gitHubToken)) { $gitHubToken = $env:GITHUB_TOKEN }
    if (-not [string]::IsNullOrWhiteSpace($gitHubToken)) {
      $headers.Authorization = "Bearer $gitHubToken"
    }
    $release = $null
    $releaseUri = 'https://api.github.com/repos/BetterDiscord/cli/releases/latest'
    $attempts = 3
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
      try {
        $release = Invoke-RestMethod -Uri $releaseUri -Headers $headers
        break
      } catch {
        if ($attempt -eq $attempts) {
          if ((Test-Path -LiteralPath $installedCli) -and (Test-Path -LiteralPath $installedMetadata)) {
            Copy-BundledBdcli -CliPath $installedCli -MetadataPath $installedMetadata -SourceLabel 'local C:\Tools\BD-AUTO\bin cache after GitHub API failure'
            return
          }
          throw
        }
        Write-Warning "BetterDiscord CLI release lookup failed on attempt $attempt/$attempts. Retrying..."
        Start-Sleep -Seconds (2 * $attempt)
      }
    }
    $asset = $release.assets |
      Where-Object { $_.name -match '(?i)bdcli_.*_windows_amd64\.zip$' -or $_.name -match '(?i)windows.*amd64.*\.zip$' } |
      Select-Object -First 1
    $checksumAsset = $release.assets | Where-Object name -eq 'bdcli_checksums.txt' | Select-Object -First 1
    if (-not $asset -or -not $checksumAsset) {
      throw 'The BetterDiscord CLI release is missing its Windows amd64 archive or checksum file.'
    }

    Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $zipPath
    Invoke-WebRequest -Uri $checksumAsset.browser_download_url -Headers $headers -OutFile $checksumPath
    $checksumLine = Get-Content -LiteralPath $checksumPath |
      Where-Object { $_ -match [regex]::Escape($asset.name) } |
      Select-Object -First 1
    if (-not $checksumLine -or $checksumLine -notmatch '^(?<hash>[A-Fa-f0-9]{64})\s+') {
      throw "Published checksum was not found for $($asset.name)."
    }

    $expectedHash = $Matches.hash.ToUpperInvariant()
    $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -ne $expectedHash) {
      throw "BetterDiscord CLI checksum mismatch. Expected $expectedHash, received $actualHash."
    }

    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    Expand-Archive -LiteralPath $zipPath -DestinationPath $tempRoot -Force
    $downloadedCli = Get-ChildItem -LiteralPath $tempRoot -Recurse -Filter 'bdcli.exe' -File |
      Select-Object -First 1
    if (-not $downloadedCli) { throw 'bdcli.exe was not found in the verified archive.' }

    $binDir = Join-Path $PayloadRoot 'bin'
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    Copy-Item -LiteralPath $downloadedCli.FullName -Destination (Join-Path $binDir 'bdcli.exe') -Force
    $metadata = [ordered]@{
      release = $release.tag_name
      asset = $asset.name
      source = $asset.browser_download_url
      sha256 = $actualHash
      staged_at = (Get-Date).ToString('o')
    }
    [System.IO.File]::WriteAllText(
      (Join-Path $binDir 'bdcli-source.json'),
      ($metadata | ConvertTo-Json),
      (New-Object System.Text.UTF8Encoding($false))
    )
    Write-Host "Bundled BetterDiscord CLI: $($release.tag_name) ($actualHash)"
  } finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $checksumPath -Force -ErrorAction SilentlyContinue
  }
}

$compilerCandidates = @(
  (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
  'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
  'C:\Program Files\Inno Setup 6\ISCC.exe'
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $compiler) {
  throw 'Inno Setup 6 compiler was not found. See BUILD.md.'
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-Repo.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Repository validation failed.' }

$resolvedBuildRoot = [System.IO.Path]::GetFullPath($buildRoot)
if (-not $resolvedBuildRoot.StartsWith([System.IO.Path]::GetFullPath($RepoRoot), [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Unsafe build path: $resolvedBuildRoot"
}
Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stagedPayload | Out-Null
Copy-Item -Path (Join-Path $RepoRoot 'payload\*') -Destination $stagedPayload -Recurse -Force
$appIconSource = Join-Path $RepoRoot 'assets\App Icon\BD-AUTO_Icon.ico'
if (-not (Test-Path -LiteralPath $appIconSource)) {
  throw "BD-AUTO app icon was not found: $appIconSource"
}
Copy-Item -LiteralPath $appIconSource -Destination (Join-Path $stagedPayload 'BD-AUTO.ico') -Force
Add-VerifiedBdcliToPayload -PayloadRoot $stagedPayload
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Generate-BrandingAssets.ps1') -OutputRoot $brandingRoot | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Branding asset generation failed.' }

$dist = Join-Path $RepoRoot 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
Remove-Item -LiteralPath (Join-Path $dist 'BD-AUTO-Setup.exe') -Force -ErrorAction SilentlyContinue

& $compiler "/DMyAppVersion=$Version" "/DMyPayloadDir=$stagedPayload" "/DMyBrandingDir=$brandingRoot" (Join-Path $RepoRoot 'installer\BD-AUTO.iss') | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE." }

$output = Join-Path $dist 'BD-AUTO-Setup.exe'
if (-not (Test-Path -LiteralPath $output)) { throw 'Installer output was not created.' }

$hash = Get-FileHash -LiteralPath $output -Algorithm SHA256
$hashLine = "$($hash.Hash)  BD-AUTO-Setup.exe"
[System.IO.File]::WriteAllText((Join-Path $dist 'BD-AUTO-Setup.exe.sha256'), $hashLine + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Built: $output"
Write-Host "SHA-256: $($hash.Hash)"
