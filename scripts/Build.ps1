[CmdletBinding()]
param(
  [ValidatePattern('^\d+\.\d+\.\d+([.-][A-Za-z0-9.-]+)?$')]
  [string]$Version
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
  $tempRoot = Join-Path $env:TEMP ("bd-auto-build-{0}" -f [guid]::NewGuid().ToString('N'))
  $zipPath = "$tempRoot.zip"
  $checksumPath = "$tempRoot-checksums.txt"
  try {
    $headers = @{ 'User-Agent' = 'BD-AUTO Build' }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/BetterDiscord/cli/releases/latest' -Headers $headers
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
