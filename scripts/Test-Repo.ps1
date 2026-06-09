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
  'INSTALL-NOTICE.txt',
  'THIRD-PARTY-NOTICES.md',
  'SECURITY.md',
  '.gitignore',
  'installer\BD-AUTO.iss',
  'payload\Install-BD-AUTO.ps1',
  'payload\Resolve-BDAutoTargetProfile.ps1',
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

$parsedManifest = Get-Content -LiteralPath (Join-Path $RepoRoot 'payload\addons.manifest.json') -Raw | ConvertFrom-Json
$manifest = @()
foreach ($entry in $parsedManifest) {
  $manifest += $entry
}
Test-Condition -Name 'Manifest count' -Passed ($manifest.Count -eq 18) -Detail "$($manifest.Count) entries"
Test-Condition -Name 'Manifest duplicate filenames' -Passed (@($manifest | Group-Object kind, file_name | Where-Object Count -gt 1).Count -eq 0) -Detail 'none'
Test-Condition -Name 'Manifest duplicate names' -Passed (@($manifest | Group-Object kind, name | Where-Object Count -gt 1).Count -eq 0) -Detail 'none'
Test-Condition -Name 'Manifest HTTPS sources' -Passed (@($manifest | Where-Object source_url -notmatch '^https://').Count -eq 0) -Detail 'all HTTPS'
Test-Condition -Name 'Manifest author credits' -Passed (@($manifest | Where-Object { [string]::IsNullOrWhiteSpace($_.author) }).Count -eq 0) -Detail 'all entries credited'
Test-Condition -Name 'Manifest project URLs' -Passed (@($manifest | Where-Object project_url -notmatch '^https://github\.com/').Count -eq 0) -Detail 'all entries linked'
Test-Condition -Name 'Manifest license classifications' -Passed (@($manifest | Where-Object { $_.license_spdx -notin @('GPL-2.0', 'MIT', 'NOASSERTION') }).Count -eq 0) -Detail 'all entries classified'
Test-Condition -Name 'No-license classifications' -Passed (@($manifest | Where-Object license_spdx -eq 'NOASSERTION').Count -eq 3) -Detail '3 explicitly identified'

$thirdPartyNotice = Get-Content -LiteralPath (Join-Path $RepoRoot 'THIRD-PARTY-NOTICES.md') -Raw
$missingNoticeFiles = @($manifest | Where-Object { $thirdPartyNotice -notmatch [regex]::Escape($_.file_name) })
Test-Condition -Name 'Add-on notice coverage' -Passed ($missingNoticeFiles.Count -eq 0) -Detail "$($manifest.Count - $missingNoticeFiles.Count)/$($manifest.Count) entries listed"
Test-Condition -Name 'License scope clarification' -Passed ($thirdPartyNotice -match "MIT license.*applies only to BD-AUTO's original") -Detail 'third-party ownership preserved'
Test-Condition -Name 'Discord terms disclosure' -Passed ($thirdPartyNotice -match 'Discord''s Terms of Service' -and $thirdPartyNotice -match 'may violate') -Detail 'risk disclosed'

$installerScript = Get-Content -LiteralPath (Join-Path $RepoRoot 'installer\BD-AUTO.iss') -Raw
Test-Condition -Name 'Installer notice page' -Passed ($installerScript -match 'InfoBeforeFile=\.\.\\INSTALL-NOTICE\.txt') -Detail 'configured'
Test-Condition -Name 'Installed legal files' -Passed ($installerScript -match 'THIRD-PARTY-NOTICES\.md' -and $installerScript -match '\.\.\\LICENSE') -Detail 'license and notices included'

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
$installScript = Get-Content -LiteralPath (Join-Path $RepoRoot 'payload\Install-BD-AUTO.ps1') -Raw
$profileResolver = Get-Content -LiteralPath (Join-Path $RepoRoot 'payload\Resolve-BDAutoTargetProfile.ps1') -Raw
Test-Condition -Name 'Logon trigger' -Passed ($taskScript -match '<LogonTrigger>') -Detail 'configured'
Test-Condition -Name 'Wake event trigger' -Passed ($taskScript -match 'Power-Troubleshooter' -and $taskScript -match 'EventID=1') -Detail 'configured'
Test-Condition -Name 'No recurring timer' -Passed ($taskScript -notmatch 'RepetitionInterval|MSFT_TaskTimeTrigger|<TimeTrigger>') -Detail 'none'
Test-Condition -Name 'Hidden task execution' -Passed ($taskScript -match '<Hidden>true</Hidden>' -and $taskScript -match '-WindowStyle Hidden') -Detail 'configured'
Test-Condition -Name 'Repair CLI refresh' -Passed ($watchdogScript -match 'Update-BdcliForRepair' -and $watchdogScript -match 'bdcli_checksums\.txt' -and $watchdogScript -match 'Get-FileHash') -Detail 'checksum verified'
Test-Condition -Name 'Target profile resolver' -Passed ($profileResolver -match 'running Discord process' -and $profileResolver -match 'interactive Explorer process' -and $profileResolver -match 'only Windows profile with Discord Stable') -Detail 'multi-source detection configured'
Test-Condition -Name 'Discord process-tree shutdown' -Passed ($profileResolver -match 'Get-BDAutoDiscordProcessIds' -and $profileResolver -match 'ParentProcessId' -and $installScript -match 'Get-BDAutoDiscordProcessIds' -and $watchdogScript -match 'Get-BDAutoDiscordProcessIds') -Detail 'hidden child processes included'
Test-Condition -Name 'Explicit profile overrides' -Passed ($installScript -match 'TargetRoamingAppData' -and $watchdogScript -match 'TargetRoamingAppData' -and $taskScript -match 'TargetRoamingAppData') -Detail 'installer, watchdog, and task support overrides'
Test-Condition -Name 'Path-bound CLI install' -Passed ($installScript -match 'install --path \$discordApp\.FullName' -and $watchdogScript -match 'install --path \$stableSignature\.Path') -Detail 'installer and repair target exact Discord app'
Test-Condition -Name 'Saved target state' -Passed ($installScript -match 'target-profile\.json' -and $watchdogScript -match 'target-profile\.json' -and $taskScript -match 'target-profile\.json') -Detail 'shared profile state configured'
Test-Condition -Name 'Original-user setup' -Passed ($installerScript -match 'ExecAsOriginalUser' -and $installerScript -match '-SkipTaskInstall') -Detail 'per-user work avoids elevated AppData'
Test-Condition -Name 'Target-bound task action' -Passed ($taskScript -match '-TargetUserName' -and $taskScript -match '-TargetLocalAppData') -Detail 'scheduled repair remains on Discord user profile'

$suspiciousPatterns = '(?i)(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|discord[_-]?token\s*[:=])'
$repositoryFiles = Get-ChildItem -LiteralPath $RepoRoot -File -Recurse |
  Where-Object { $_.FullName -notmatch '\\.git\\|\\dist\\|\\build\\' }
$suspicious = @($repositoryFiles | Select-String -Pattern $suspiciousPatterns -ErrorAction SilentlyContinue)
Test-Condition -Name 'Secret scan' -Passed ($suspicious.Count -eq 0) -Detail "$($suspicious.Count) suspicious match(es)"

$trackedFiles = @(& git -C $RepoRoot ls-files)
$forbiddenTracked = @($trackedFiles | Where-Object {
  $_ -match '(^|/)(logs|backups|bin|BetterDiscord)(/|$)' -or
  $_ -match '(^|/)state\.json$' -or
  $_ -match '\.(exe|dll|zip|7z|rar|log)$'
})
Test-Condition -Name 'Clean tracked files' -Passed ($forbiddenTracked.Count -eq 0) -Detail "$($forbiddenTracked.Count) forbidden tracked file(s)"

if ($failures.Count -gt 0) {
  Write-Host "`nRepository validation failed:"
  $failures | ForEach-Object { Write-Host " - $_" }
  exit 1
}

Write-Host "`nRepository validation passed."
