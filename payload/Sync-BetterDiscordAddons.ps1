[CmdletBinding()]
param(
  [string]$ManifestPath = (Join-Path $PSScriptRoot 'addons.manifest.json'),
  [string]$ActiveRoot = (Join-Path $env:APPDATA 'BetterDiscord'),
  [string]$CacheRoot = (Join-Path $PSScriptRoot 'BetterDiscord'),
  [switch]$Prune,
  [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'

function Write-SyncLog {
  param([string]$Message, [string]$Level = 'INFO')
  Write-Host ("[{0}] [ADDONS] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

function Get-AddonMetadata {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
  $nameMatch = [regex]::Match($text, '(?im)^\s*(?:/\*\*|\*)?\s*@name\s+([^\r\n*]+)')
  $versionMatch = [regex]::Match($text, '(?im)^\s*(?:/\*\*|\*)?\s*@version\s+([^\s*]+)')

  return [pscustomobject]@{
    Name = if ($nameMatch.Success) { $nameMatch.Groups[1].Value.Trim() } else { $null }
    Version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value.Trim() } else { $null }
  }
}

function Test-AddonFile {
  param(
    [string]$Path,
    [pscustomobject]$Addon
  )

  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  $item = Get-Item -LiteralPath $Path
  if ($item.Length -le 0) { return $false }

  try {
    $metadata = Get-AddonMetadata -Path $Path
    if (-not $metadata) { return $false }
    if ([string]::IsNullOrWhiteSpace($metadata.Name) -or $metadata.Name -ine $Addon.name) { return $false }
    if ($Addon.version -and ([string]::IsNullOrWhiteSpace($metadata.Version) -or $metadata.Version -ne $Addon.version)) { return $false }
    return $true
  } catch {
    return $false
  }
}

function Copy-AddonFile {
  param([string]$Source, [string]$Destination)

  $destinationDir = Split-Path -Parent $Destination
  New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
  $tempDestination = "$Destination.tmp-$([guid]::NewGuid().ToString('N'))"
  try {
    Copy-Item -LiteralPath $Source -Destination $tempDestination -Force
    Move-Item -LiteralPath $tempDestination -Destination $Destination -Force
  } finally {
    Remove-Item -LiteralPath $tempDestination -Force -ErrorAction SilentlyContinue
  }
}

function Write-JsonAtomic {
  param([string]$Path, [hashtable]$Value)

  $json = $Value | ConvertTo-Json -Depth 4
  $tempPath = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
  try {
    [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
  } finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
  }
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "Addon manifest not found: $ManifestPath"
}

$manifest = @(Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json)
if ($manifest.Count -eq 0) { throw 'Addon manifest is empty.' }

$duplicateFiles = $manifest | Group-Object kind, file_name | Where-Object Count -gt 1
$duplicateNames = $manifest | Group-Object kind, name | Where-Object Count -gt 1
if ($duplicateFiles) { throw "Duplicate addon file entries: $($duplicateFiles.Name -join ', ')" }
if ($duplicateNames) { throw "Duplicate addon name entries: $($duplicateNames.Name -join ', ')" }

$activeDataDir = Join-Path $ActiveRoot 'data\stable'
$roots = @($CacheRoot, $ActiveRoot) | Select-Object -Unique
if (-not $VerifyOnly) {
  New-Item -ItemType Directory -Force -Path $activeDataDir | Out-Null
  foreach ($root in $roots) {
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'plugins'), (Join-Path $root 'themes') | Out-Null
  }
}

$enabled = @($manifest | Where-Object enabled)
$pluginFiles = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$themeFiles = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$pluginState = @{}
$themeState = @{}
$downloadCount = 0
$copyCount = 0
$keepCount = 0
$problems = New-Object System.Collections.Generic.List[string]

foreach ($addon in $enabled) {
  if ($addon.kind -notin @('plugin', 'theme')) {
    $problems.Add("Unsupported addon kind '$($addon.kind)' for $($addon.name)")
    continue
  }
  if ($addon.source_url -notmatch '^https://') {
    $problems.Add("Non-HTTPS source URL for $($addon.name)")
    continue
  }

  $relativeDir = if ($addon.kind -eq 'plugin') { 'plugins' } else { 'themes' }
  $cachePath = Join-Path (Join-Path $CacheRoot $relativeDir) $addon.file_name
  $activePath = Join-Path (Join-Path $ActiveRoot $relativeDir) $addon.file_name
  $cacheValid = Test-AddonFile -Path $cachePath -Addon $addon
  $activeValid = Test-AddonFile -Path $activePath -Addon $addon

  if ($addon.kind -eq 'plugin') {
    [void]$pluginFiles.Add($addon.file_name)
    $pluginState[$addon.name] = $true
  } else {
    [void]$themeFiles.Add($addon.file_name)
    $themeState[$addon.name] = $true
  }

  if ($VerifyOnly) {
    if (-not $activeValid) { $problems.Add("Missing or outdated active addon: $($addon.file_name)") }
    if (-not $cacheValid) { $problems.Add("Missing or outdated cached addon: $($addon.file_name)") }
    continue
  }

  $sourcePath = $null
  if ($cacheValid) {
    $sourcePath = $cachePath
  } elseif ($activeValid) {
    $sourcePath = $activePath
  } else {
    $downloadPath = Join-Path $env:TEMP ("bd-auto-{0}" -f ([guid]::NewGuid().ToString('N')))
    try {
      Write-SyncLog "Downloading $($addon.name) $($addon.version)"
      Invoke-WebRequest -Uri $addon.source_url -OutFile $downloadPath
      if (-not (Test-AddonFile -Path $downloadPath -Addon $addon)) {
        throw "Downloaded addon failed metadata validation: $($addon.file_name)"
      }
      Copy-AddonFile -Source $downloadPath -Destination $cachePath
      $sourcePath = $cachePath
      $cacheValid = $true
      $downloadCount++
    } finally {
      Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
    }
  }

  if (-not $cacheValid) {
    Copy-AddonFile -Source $sourcePath -Destination $cachePath
    $cacheValid = $true
    $copyCount++
  }
  if (-not $activeValid) {
    Copy-AddonFile -Source $sourcePath -Destination $activePath
    $copyCount++
  } else {
    $keepCount++
  }
}

if ($Prune) {
  foreach ($root in $roots) {
    $pluginDir = Join-Path $root 'plugins'
    $themeDir = Join-Path $root 'themes'
    if (Test-Path -LiteralPath $pluginDir) {
      Get-ChildItem -LiteralPath $pluginDir -File -Filter '*.plugin.js' -ErrorAction SilentlyContinue |
        Where-Object { -not $pluginFiles.Contains($_.Name) } |
        ForEach-Object {
          if ($VerifyOnly) { $problems.Add("Unexpected plugin file: $($_.FullName)") }
          else {
            Write-SyncLog "Removing unmanaged plugin file $($_.Name)"
            Remove-Item -LiteralPath $_.FullName -Force
          }
        }
    }
    if (Test-Path -LiteralPath $themeDir) {
      Get-ChildItem -LiteralPath $themeDir -File -Filter '*.theme.css' -ErrorAction SilentlyContinue |
        Where-Object { -not $themeFiles.Contains($_.Name) } |
        ForEach-Object {
          if ($VerifyOnly) { $problems.Add("Unexpected theme file: $($_.FullName)") }
          else {
            Write-SyncLog "Removing unmanaged theme file $($_.Name)"
            Remove-Item -LiteralPath $_.FullName -Force
          }
        }
    }
  }
}

if ($VerifyOnly) {
  if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-SyncLog $_ 'ERROR' }
    throw "Addon verification failed with $($problems.Count) problem(s)."
  }
  Write-SyncLog "Verified $($enabled.Count) addon(s)."
  exit 0
}

Write-JsonAtomic -Path (Join-Path $activeDataDir 'plugins.json') -Value $pluginState
Write-JsonAtomic -Path (Join-Path $activeDataDir 'themes.json') -Value $themeState
Write-SyncLog "Sync complete: enabled=$($enabled.Count), downloaded=$downloadCount, copied=$copyCount, unchanged=$keepCount"
