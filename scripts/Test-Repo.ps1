[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]

function Test-Condition {
  param([string]$Name, [bool]$Passed, [string]$Detail)
  if ($Passed) {
    Write-Host "[PASS] $Name - $Detail"
  } else {
    Write-Host "[FAIL] $Name - $Detail"
    $failures.Add("${Name}: $Detail")
  }
}

$requiredFiles = @(
  'README.md',
  'BUILD.md',
  'LICENSE',
  'SECURITY.md',
  '.gitignore',
  'installer\BD-AUTO.iss',
  'payload\Install-BD-AUTO.ps1',
  'payload\Sync-BetterDiscordAddons.ps1',
  'payload\addons.manifest.json',
  'payload\BetterDiscordWatchdog\BetterDiscord-Watchdog.ps1',
  'payload\BetterDiscordWatchdog\Install-BetterDiscord-WatchdogTask.ps1',
  'payload\BetterDiscordWatchdog\Remove-BetterDiscord-WatchdogTask.ps1'
)
foreach ($file in $requiredFiles) {
  Test-Condition -Name "Required $file" -Passed (Test-Path -LiteralPath (Join-Path $RepoRoot $file)) -Detail 'present'
}

$powerShellFiles = Get-ChildItem -LiteralPath $RepoRoot -Filter '*.ps1' -File -Recurse |
  Where-Object { $_.FullName -notmatch '\\dist\\|\\build\\' }
foreach ($file in $powerShellFiles) {
  $tokens = $null
  $parseErrors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
  Test-Condition -Name "Syntax $($file.Name)" -Passed (-not $parseErrors) -Detail $(if ($parseErrors) { $parseErrors[0].Message } else { 'valid' })
}

$manifest = @(Get-Content -LiteralPath (Join-Path $RepoRoot 'payload\addons.manifest.json') -Raw | ConvertFrom-Json)
Test-Condition -Name 'Manifest count' -Passed ($manifest.Count -eq 18) -Detail "$($manifest.Count) entries"
Test-Condition -Name 'Manifest duplicate filenames' -Passed (@($manifest | Group-Object kind, file_name | Where-Object Count -gt 1).Count -eq 0) -Detail 'none'
Test-Condition -Name 'Manifest duplicate names' -Passed (@($manifest | Group-Object kind, name | Where-Object Count -gt 1).Count -eq 0) -Detail 'none'
Test-Condition -Name 'Manifest HTTPS sources' -Passed (@($manifest | Where-Object source_url -notmatch '^https://').Count -eq 0) -Detail 'all HTTPS'

$forbiddenNames = @('state.json')
$forbiddenDirectories = @('logs', 'backups', 'bin', 'BetterDiscord')
$forbiddenExtensions = @('.exe', '.dll', '.zip', '.7z', '.rar', '.log')
$payloadFiles = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'payload') -File -Recurse
$payloadDirectories = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'payload') -Directory -Recurse
$forbiddenFiles = @($payloadFiles | Where-Object {
  $_.Name -in $forbiddenNames -or $_.Extension -in $forbiddenExtensions
})
$forbiddenDirs = @($payloadDirectories | Where-Object { $_.Name -in $forbiddenDirectories })
Test-Condition -Name 'Clean payload files' -Passed ($forbiddenFiles.Count -eq 0) -Detail "$($forbiddenFiles.Count) forbidden file(s)"
Test-Condition -Name 'Clean payload directories' -Passed ($forbiddenDirs.Count -eq 0) -Detail "$($forbiddenDirs.Count) forbidden folder(s)"

$taskScript = Get-Content -LiteralPath (Join-Path $RepoRoot 'payload\BetterDiscordWatchdog\Install-BetterDiscord-WatchdogTask.ps1') -Raw
$watchdogScript = Get-Content -LiteralPath (Join-Path $RepoRoot 'payload\BetterDiscordWatchdog\BetterDiscord-Watchdog.ps1') -Raw
Test-Condition -Name 'Logon trigger' -Passed ($taskScript -match '<LogonTrigger>') -Detail 'configured'
Test-Condition -Name 'Wake event trigger' -Passed ($taskScript -match 'Power-Troubleshooter' -and $taskScript -match 'EventID=1') -Detail 'configured'
Test-Condition -Name 'No recurring timer' -Passed ($taskScript -notmatch 'RepetitionInterval|MSFT_TaskTimeTrigger|<TimeTrigger>') -Detail 'none'
Test-Condition -Name 'Hidden task execution' -Passed ($taskScript -match '<Hidden>true</Hidden>' -and $taskScript -match '-WindowStyle Hidden') -Detail 'configured'
Test-Condition -Name 'Repair CLI refresh' -Passed ($watchdogScript -match 'Update-BdcliForRepair' -and $watchdogScript -match 'bdcli_checksums\.txt' -and $watchdogScript -match 'Get-FileHash') -Detail 'checksum verified'

$suspiciousPatterns = '(?i)(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|discord[_-]?token\s*[:=])'
$suspicious = @($payloadFiles | Select-String -Pattern $suspiciousPatterns -ErrorAction SilentlyContinue)
Test-Condition -Name 'Secret scan' -Passed ($suspicious.Count -eq 0) -Detail "$($suspicious.Count) suspicious match(es)"

if ($failures.Count -gt 0) {
  Write-Host "`nRepository validation failed:"
  $failures | ForEach-Object { Write-Host " - $_" }
  exit 1
}

Write-Host "`nRepository validation passed."
