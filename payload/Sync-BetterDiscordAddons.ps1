[CmdletBinding()]
param(
  [string]$ManifestPath = (Join-Path $PSScriptRoot 'addons.manifest.json'),
  [string]$ActiveRoot = (Join-Path $env:APPDATA 'BetterDiscord'),
  [string]$CacheRoot = (Join-Path $PSScriptRoot 'BetterDiscord'),
  [string]$BackupRoot,
  [string]$ReportPath,
  [string]$SourceOverrideRoot,
  [switch]$Prune,
  [switch]$RemoveRecognizedDuplicates,
  [switch]$VerifyOnly,
  [switch]$AuditOnly,
  [switch]$NoSourceCheck
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-SyncLog {
  param([string]$Message, [string]$Level = 'INFO')
  Write-Host ("[{0}] [ADDONS] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
}

function Write-JsonAtomic {
  param([string]$Path, $Value, [int]$Depth = 8)

  $parent = Split-Path -Parent $Path
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $tempPath = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
  try {
    $json = $Value | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
  } finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
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

function Get-AddonMetadata {
  param([string]$Path, [pscustomobject]$Addon)

  if (-not (Test-Path -LiteralPath $Path)) {
    return [pscustomobject]@{
      Path = $Path
      Exists = $false
      Valid = $false
      Name = $null
      Version = $null
      Length = 0
      Sha256 = $null
      LastWriteTime = $null
      ValidationError = 'file missing'
    }
  }

  try {
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -le 0) { throw 'file is empty' }
    $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    $nameMatch = [regex]::Match($text, '(?im)^\s*(?:/\*\*|\*)?\s*@name\s+([^\r\n*]+)')
    $versionMatch = [regex]::Match($text, '(?im)^\s*(?:/\*\*|\*)?\s*@version\s+([^\s*]+)')
    $name = if ($nameMatch.Success) { $nameMatch.Groups[1].Value.Trim() } else { $null }
    $version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value.Trim() } else { $null }
    $expectedNames = @($Addon.name)
    if ($Addon.PSObject.Properties.Name -contains 'accepted_names') {
      $expectedNames += @($Addon.accepted_names)
    }
    $nameValid = -not [string]::IsNullOrWhiteSpace($name) -and @($expectedNames | Where-Object { $_ -ieq $name }).Count -gt 0
    return [pscustomobject]@{
      Path = $Path
      Exists = $true
      Valid = $nameValid
      Name = $name
      Version = $version
      Length = $item.Length
      Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
      LastWriteTime = $item.LastWriteTime.ToString('o')
      ValidationError = if ($nameValid) { $null } else { "metadata name '$name' does not match '$($Addon.name)'" }
    }
  } catch {
    return [pscustomobject]@{
      Path = $Path
      Exists = $true
      Valid = $false
      Name = $null
      Version = $null
      Length = 0
      Sha256 = $null
      LastWriteTime = $null
      ValidationError = $_.Exception.Message
    }
  }
}

function ConvertTo-VersionParts {
  param([string]$Version)

  if ([string]::IsNullOrWhiteSpace($Version)) { return $null }
  $matches = [regex]::Matches($Version.Trim(), '\d+')
  if ($matches.Count -eq 0) { return $null }
  $parts = New-Object System.Collections.Generic.List[long]
  foreach ($match in $matches) {
    $number = 0L
    if (-not [long]::TryParse($match.Value, [ref]$number)) { return $null }
    $parts.Add($number)
  }
  return ,$parts.ToArray()
}

function Compare-AddonVersion {
  param([string]$Left, [string]$Right)

  $leftParts = ConvertTo-VersionParts -Version $Left
  $rightParts = ConvertTo-VersionParts -Version $Right
  if ($null -eq $leftParts -or $null -eq $rightParts) { return $null }
  $count = [math]::Max($leftParts.Count, $rightParts.Count)
  for ($index = 0; $index -lt $count; $index++) {
    $leftValue = if ($index -lt $leftParts.Count) { $leftParts[$index] } else { 0 }
    $rightValue = if ($index -lt $rightParts.Count) { $rightParts[$index] } else { 0 }
    if ($leftValue -gt $rightValue) { return 1 }
    if ($leftValue -lt $rightValue) { return -1 }
  }
  return 0
}

function Backup-AddonFile {
  param([string]$Path, [string]$RelativeDirectory)

  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
  $destination = Join-Path (Join-Path $BackupRoot $stamp) (Join-Path $RelativeDirectory (Split-Path -Leaf $Path))
  Copy-AddonFile -Source $Path -Destination $destination
  return $destination
}

function Get-UpstreamAddon {
  param([pscustomobject]$Addon, [string]$DownloadPath)

  if ($NoSourceCheck) {
    return [pscustomobject]@{
      Metadata = (Get-AddonMetadata -Path $DownloadPath -Addon $Addon)
      Status = 'source check disabled'
    }
  }

  try {
    if ($SourceOverrideRoot) {
      $overridePath = Join-Path $SourceOverrideRoot $Addon.file_name
      if (-not (Test-Path -LiteralPath $overridePath)) { throw "source override missing: $overridePath" }
      Copy-Item -LiteralPath $overridePath -Destination $DownloadPath -Force
    } else {
      if ($Addon.source_url -notmatch '^https://') { throw 'source URL is not HTTPS' }
      Invoke-WebRequest -Uri $Addon.source_url -OutFile $DownloadPath -UseBasicParsing
    }
    $metadata = Get-AddonMetadata -Path $DownloadPath -Addon $Addon
    if (-not $metadata.Valid) { throw $metadata.ValidationError }
    return [pscustomobject]@{
      Metadata = $metadata
      Status = 'available'
    }
  } catch {
    Remove-Item -LiteralPath $DownloadPath -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{
      Metadata = (Get-AddonMetadata -Path $DownloadPath -Addon $Addon)
      Status = "unavailable: $($_.Exception.Message)"
    }
  }
}

function Get-PreferredCandidate {
  param($Installed, $Upstream, $Cached, [bool]$FallbackAllowed)

  if ($Installed.Valid) {
    if ($Upstream.Valid) {
      $sourceComparison = Compare-AddonVersion -Left $Upstream.Version -Right $Installed.Version
      if ($null -eq $sourceComparison) {
        return [pscustomobject]@{ Candidate = $Installed; Origin = 'installed'; Decision = 'preserved installed version because source comparison was unknown' }
      }
      if ($sourceComparison -gt 0) {
        return [pscustomobject]@{ Candidate = $Upstream; Origin = 'upstream'; Decision = 'updated from newer upstream version' }
      }
      if ($sourceComparison -lt 0) {
        return [pscustomobject]@{ Candidate = $Installed; Origin = 'installed'; Decision = 'preserved installed newer version' }
      }
      return [pscustomobject]@{ Candidate = $Installed; Origin = 'installed'; Decision = 'preserved installed version matching upstream' }
    }

    if ($FallbackAllowed -and $Cached.Valid) {
      $cacheComparison = Compare-AddonVersion -Left $Cached.Version -Right $Installed.Version
      if ($null -ne $cacheComparison -and $cacheComparison -gt 0) {
        return [pscustomobject]@{ Candidate = $Cached; Origin = 'cache'; Decision = 'restored newer cached fallback because source was unavailable' }
      }
      if ($null -eq $cacheComparison) {
        return [pscustomobject]@{ Candidate = $Installed; Origin = 'installed'; Decision = 'preserved installed version because cache comparison was unknown' }
      }
    }
    return [pscustomobject]@{ Candidate = $Installed; Origin = 'installed'; Decision = 'preserved installed version; source unavailable and cache was not newer' }
  }

  if ($Upstream.Valid) {
    return [pscustomobject]@{ Candidate = $Upstream; Origin = 'upstream'; Decision = 'installed missing or invalid; restored from upstream' }
  }
  if ($FallbackAllowed -and $Cached.Valid) {
    return [pscustomobject]@{ Candidate = $Cached; Origin = 'cache'; Decision = 'installed missing or invalid; restored from cached fallback' }
  }
  return [pscustomobject]@{ Candidate = $null; Origin = 'none'; Decision = 'no valid installed, upstream, or allowed cached copy' }
}

if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Addon manifest not found: $ManifestPath" }
if (-not $BackupRoot) { $BackupRoot = Join-Path $CacheRoot 'backups\addon-sync' }
if (-not $ReportPath) { $ReportPath = Join-Path $ActiveRoot 'data\stable\bd-auto-addon-audit.json' }

$parsedManifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$manifest = @()
foreach ($entry in $parsedManifest) { $manifest += $entry }
if ($manifest.Count -eq 0) { throw 'Addon manifest is empty.' }

$duplicateFiles = @($manifest | Group-Object kind, file_name | Where-Object Count -gt 1)
$duplicateNames = @($manifest | Group-Object kind, name | Where-Object Count -gt 1)
if ($duplicateFiles.Count -gt 0) { throw "Duplicate addon file entries: $($duplicateFiles.Name -join ', ')" }
if ($duplicateNames.Count -gt 0) { throw "Duplicate addon name entries: $($duplicateNames.Name -join ', ')" }

$readOnly = [bool]($VerifyOnly -or $AuditOnly)
$activeDataDir = Join-Path $ActiveRoot 'data\stable'
$roots = @($CacheRoot, $ActiveRoot) | Select-Object -Unique
if (-not $readOnly) {
  New-Item -ItemType Directory -Force -Path $activeDataDir, $BackupRoot | Out-Null
  foreach ($root in $roots) {
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'plugins'), (Join-Path $root 'themes') | Out-Null
  }
}

$enabled = @($manifest | Where-Object enabled)
$pluginFiles = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$themeFiles = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$pluginState = @{}
$themeState = @{}
$results = New-Object System.Collections.Generic.List[object]
$problems = New-Object System.Collections.Generic.List[string]
$changedCount = 0
$preservedCount = 0
$backupCount = 0

foreach ($addon in $enabled) {
  if ($addon.kind -notin @('plugin', 'theme')) {
    $problems.Add("Unsupported addon kind '$($addon.kind)' for $($addon.name)")
    continue
  }

  $relativeDir = if ($addon.kind -eq 'plugin') { 'plugins' } else { 'themes' }
  $cachePath = Join-Path (Join-Path $CacheRoot $relativeDir) $addon.file_name
  $activePath = Join-Path (Join-Path $ActiveRoot $relativeDir) $addon.file_name
  $downloadPath = Join-Path $env:TEMP ("bd-auto-source-{0}-{1}" -f ([guid]::NewGuid().ToString('N')), $addon.file_name)
  $fallbackAllowed = $true
  if ($addon.PSObject.Properties.Name -contains 'fallback_allowed') {
    $fallbackAllowed = [bool]$addon.fallback_allowed
  }

  if ($addon.kind -eq 'plugin') {
    [void]$pluginFiles.Add($addon.file_name)
    $pluginState[$addon.name] = $true
  } else {
    [void]$themeFiles.Add($addon.file_name)
    $themeState[$addon.name] = $true
  }

  try {
    $installed = Get-AddonMetadata -Path $activePath -Addon $addon
    $cached = Get-AddonMetadata -Path $cachePath -Addon $addon
    $sourceResult = Get-UpstreamAddon -Addon $addon -DownloadPath $downloadPath
    $upstream = $sourceResult.Metadata
    $selection = Get-PreferredCandidate -Installed $installed -Upstream $upstream -Cached $cached -FallbackAllowed $fallbackAllowed
    $backupPath = $null
    $action = $selection.Decision

    if (-not $selection.Candidate) {
      $problems.Add("$($addon.file_name): $action")
    } elseif ($readOnly) {
      if (-not $installed.Valid) {
        $action = "would restore from $($selection.Origin)"
        $changedCount++
        if ($VerifyOnly) { $problems.Add("Missing or invalid active addon: $($addon.file_name)") }
      } elseif ($selection.Origin -ne 'installed') {
        $action = "would $($selection.Decision)"
        $changedCount++
      } else {
        $preservedCount++
      }
    } else {
      if ($selection.Origin -ne 'installed') {
        if ($installed.Exists) {
          $backupPath = Backup-AddonFile -Path $activePath -RelativeDirectory $relativeDir
          if ($backupPath) { $backupCount++ }
        }
        Copy-AddonFile -Source $selection.Candidate.Path -Destination $activePath
        $installed = Get-AddonMetadata -Path $activePath -Addon $addon
        $changedCount++
      } else {
        $preservedCount++
      }

      $refreshCache = -not $cached.Valid
      if ($installed.Valid -and $cached.Valid) {
        $installedVsCache = Compare-AddonVersion -Left $installed.Version -Right $cached.Version
        $refreshCache = $null -ne $installedVsCache -and $installedVsCache -gt 0
      }
      if ($installed.Valid -and $refreshCache) {
        Copy-AddonFile -Source $activePath -Destination $cachePath
        $cached = Get-AddonMetadata -Path $cachePath -Addon $addon
        $action += '; refreshed fallback cache from installed copy'
      }
    }

    $downgradeRisk = $false
    if ($installed.Valid -and $selection.Candidate -and $selection.Origin -ne 'installed') {
      $candidateVsInstalled = Compare-AddonVersion -Left $selection.Candidate.Version -Right $installed.Version
      $downgradeRisk = $null -ne $candidateVsInstalled -and $candidateVsInstalled -lt 0
    }
    if ($downgradeRisk) {
      $problems.Add("Downgrade risk detected for $($addon.file_name)")
    }

    Write-SyncLog "$($addon.file_name): $action"
    $results.Add([pscustomobject][ordered]@{
      addon_id = if ($addon.addon_id) { $addon.addon_id } else { $addon.name }
      name = $addon.name
      kind = $addon.kind
      file_name = $addon.file_name
      source_repo = $addon.source_repo
      source_url = $addon.source_url
      source_status = $sourceResult.Status
      manifest_baseline_version = $addon.version
      installed_path = $activePath
      installed_version = $installed.Version
      installed_sha256 = $installed.Sha256
      installed_write_time = $installed.LastWriteTime
      cache_path = $cachePath
      cached_version = $cached.Version
      cached_sha256 = $cached.Sha256
      cached_write_time = $cached.LastWriteTime
      upstream_version = $upstream.Version
      upstream_sha256 = $upstream.Sha256
      upstream_checked_at = (Get-Date).ToString('o')
      selected_origin = $selection.Origin
      action = $action
      downgrade_risk = $downgradeRisk
      backup_path = $backupPath
    })
  } finally {
    Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue
  }
}

if ($RemoveRecognizedDuplicates) {
  foreach ($root in $roots) {
    foreach ($kind in @('plugin', 'theme')) {
      $relativeDir = if ($kind -eq 'plugin') { 'plugins' } else { 'themes' }
      $filter = if ($kind -eq 'plugin') { '*.plugin.js' } else { '*.theme.css' }
      $directory = Join-Path $root $relativeDir
      if (-not (Test-Path -LiteralPath $directory)) { continue }
      foreach ($addon in @($enabled | Where-Object kind -eq $kind)) {
        $canonicalPath = Join-Path $directory $addon.file_name
        $duplicates = @(Get-ChildItem -LiteralPath $directory -File -Filter $filter -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -ine $canonicalPath } |
          Where-Object { (Get-AddonMetadata -Path $_.FullName -Addon $addon).Valid })
        foreach ($duplicate in $duplicates) {
          if ($readOnly) {
            $problems.Add("Recognized duplicate addon: $($duplicate.FullName)")
          } else {
            Write-SyncLog "Removing recognized duplicate $($duplicate.Name); canonical file is $($addon.file_name)"
            Remove-Item -LiteralPath $duplicate.FullName -Force
          }
        }
      }
    }
  }
}

if ($Prune) {
  foreach ($root in $roots) {
    foreach ($kind in @('plugin', 'theme')) {
      $relativeDir = if ($kind -eq 'plugin') { 'plugins' } else { 'themes' }
      $filter = if ($kind -eq 'plugin') { '*.plugin.js' } else { '*.theme.css' }
      $knownFiles = if ($kind -eq 'plugin') { $pluginFiles } else { $themeFiles }
      $directory = Join-Path $root $relativeDir
      if (-not (Test-Path -LiteralPath $directory)) { continue }
      Get-ChildItem -LiteralPath $directory -File -Filter $filter -ErrorAction SilentlyContinue |
        Where-Object { -not $knownFiles.Contains($_.Name) } |
        ForEach-Object {
          if ($readOnly) {
            $problems.Add("Unexpected $kind file: $($_.FullName)")
          } else {
            Write-SyncLog "Removing unmanaged $kind file $($_.Name)"
            Remove-Item -LiteralPath $_.FullName -Force
          }
        }
    }
  }
}

if (-not $readOnly) {
  Write-JsonAtomic -Path (Join-Path $activeDataDir 'plugins.json') -Value $pluginState -Depth 4
  Write-JsonAtomic -Path (Join-Path $activeDataDir 'themes.json') -Value $themeState -Depth 4
}

$report = [ordered]@{
  generated_at = (Get-Date).ToString('o')
  mode = if ($AuditOnly) { 'audit' } elseif ($VerifyOnly) { 'verify' } else { 'sync' }
  manifest_path = $ManifestPath
  active_root = $ActiveRoot
  cache_root = $CacheRoot
  backup_root = $BackupRoot
  addon_count = $enabled.Count
  changed_count = $changedCount
  preserved_count = $preservedCount
  problem_count = $problems.Count
  problems = @($problems | ForEach-Object { $_ })
  addons = @($results | ForEach-Object { $_ })
}
Write-JsonAtomic -Path $ReportPath -Value $report -Depth 10
Write-SyncLog "Report written: $ReportPath"

if ($problems.Count -gt 0) {
  $problems | ForEach-Object { Write-SyncLog $_ 'ERROR' }
  throw "Addon operation completed with $($problems.Count) problem(s)."
}

Write-SyncLog "Complete: enabled=$($enabled.Count), changed=$changedCount, preserved=$preservedCount, backups=$backupCount"
