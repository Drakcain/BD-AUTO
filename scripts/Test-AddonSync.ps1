[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$SyncScript = Join-Path $RepoRoot 'payload\Sync-BetterDiscordAddons.ps1'
$TestRoot = Join-Path $env:TEMP ("bd-auto-addon-test-{0}" -f [guid]::NewGuid().ToString('N'))
$ActiveRoot = Join-Path $TestRoot 'active'
$CacheRoot = Join-Path $TestRoot 'cache'
$SourceRoot = Join-Path $TestRoot 'source'
$BackupRoot = Join-Path $TestRoot 'backups'
$ManifestPath = Join-Path $TestRoot 'manifest.json'
$ReportPath = Join-Path $TestRoot 'report.json'
$FileName = '0BDFDB.plugin.js'

function Write-TestAddon {
  param([string]$Path, [AllowNull()][string]$Version, [string]$Marker)

  $parent = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  $versionLine = if ($null -ne $Version) { " * @version $Version`r`n" } else { '' }
  $content = "/**`r`n * @name BDFDB`r`n$versionLine */`r`n// $Marker`r`n"
  [System.IO.File]::WriteAllText($Path, $content, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-TestVersion {
  param([string]$Path)
  $text = Get-Content -LiteralPath $Path -Raw
  $match = [regex]::Match($text, '(?im)^\s*\*\s*@version\s+([^\s*]+)')
  if ($match.Success) { return $match.Groups[1].Value }
  return $null
}

function Invoke-TestSync {
  $arguments = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', $SyncScript,
    '-ManifestPath', $ManifestPath,
    '-ActiveRoot', $ActiveRoot,
    '-CacheRoot', $CacheRoot,
    '-BackupRoot', $BackupRoot,
    '-ReportPath', $ReportPath,
    '-SourceOverrideRoot', $SourceRoot
  )
  & powershell.exe @arguments | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "Addon sync test process exited with code $LASTEXITCODE" }
  return Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json
}

function Assert-Equal {
  param($Expected, $Actual, [string]$Message)
  if ($Expected -ne $Actual) {
    throw "$Message Expected '$Expected', received '$Actual'."
  }
  Write-Host "[PASS] $Message"
}

try {
  New-Item -ItemType Directory -Force -Path $ActiveRoot, $CacheRoot, $SourceRoot, $BackupRoot | Out-Null
  @(
    [ordered]@{
      addon_id = 'test-bdfdb'
      kind = 'plugin'
      file_name = $FileName
      name = 'BDFDB'
      version = '4.5.4'
      author = 'DevilBro'
      source_repo = 'mwittrien/BetterDiscordAddons'
      project_url = 'https://github.com/mwittrien/BetterDiscordAddons'
      license_spdx = 'GPL-2.0'
      source_url = 'https://example.invalid/0BDFDB.plugin.js'
      update_policy = 'source-preferred-no-downgrade'
      fallback_allowed = $true
      enabled = $true
    }
  ) | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8

  $activeFile = Join-Path (Join-Path $ActiveRoot 'plugins') $FileName
  $cacheFile = Join-Path (Join-Path $CacheRoot 'plugins') $FileName
  $sourceFile = Join-Path $SourceRoot $FileName

  Write-TestAddon -Path $activeFile -Version '4.5.4' -Marker 'installed-newer'
  Write-TestAddon -Path $cacheFile -Version '4.5.3' -Marker 'cache-older'
  Write-TestAddon -Path $sourceFile -Version '4.5.3' -Marker 'source-older'
  $report = Invoke-TestSync
  Assert-Equal '4.5.4' (Get-TestVersion -Path $activeFile) 'Newer installed BDFDB is preserved'
  Assert-Equal '4.5.4' (Get-TestVersion -Path $cacheFile) 'Fallback cache follows newer installed BDFDB'
  Assert-Equal 'installed' $report.addons[0].selected_origin 'Installed copy wins downgrade comparison'

  Write-TestAddon -Path $sourceFile -Version '4.5.5' -Marker 'source-newer'
  $report = Invoke-TestSync
  Assert-Equal '4.5.5' (Get-TestVersion -Path $activeFile) 'Newer upstream BDFDB is installed'
  Assert-Equal 'upstream' $report.addons[0].selected_origin 'Upstream copy wins upgrade comparison'
  if (-not $report.addons[0].backup_path -or -not (Test-Path -LiteralPath $report.addons[0].backup_path)) {
    throw 'Upstream replacement did not create a backup.'
  }
  Write-Host '[PASS] Upstream replacement creates a backup'

  Remove-Item -LiteralPath $sourceFile -Force
  Write-TestAddon -Path $activeFile -Version '4.5.5' -Marker 'installed-old'
  Write-TestAddon -Path $cacheFile -Version '4.5.6' -Marker 'cache-newer'
  $report = Invoke-TestSync
  Assert-Equal '4.5.6' (Get-TestVersion -Path $activeFile) 'Newer cache restores when upstream is unavailable'
  Assert-Equal 'cache' $report.addons[0].selected_origin 'Cache is fallback-only'

  Write-TestAddon -Path $activeFile -Version $null -Marker 'installed-unknown'
  Write-TestAddon -Path $cacheFile -Version '4.5.3' -Marker 'cache-known'
  Write-TestAddon -Path $sourceFile -Version '4.5.3' -Marker 'source-known'
  $report = Invoke-TestSync
  Assert-Equal $null (Get-TestVersion -Path $activeFile) 'Unknown installed version is preserved on ambiguous comparison'
  Assert-Equal 'installed' $report.addons[0].selected_origin 'Unknown comparison never overwrites installed copy'

  Write-Host 'Addon synchronization regression tests passed.'
} finally {
  Remove-Item -LiteralPath $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
