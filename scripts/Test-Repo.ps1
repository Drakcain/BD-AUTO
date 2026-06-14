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
  'VERSION',
  'README.md',
  'BUILD.md',
  'LICENSE',
  'INSTALL-NOTICE.txt',
  'THIRD-PARTY-NOTICES.md',
  'SIGNING.md',
  'SECURITY.md',
  '.gitignore',
  'installer\BD-AUTO.iss',
  'payload\Install-BD-AUTO.ps1',
  'payload\Install-BD-AUTO.cmd',
  'payload\Get-BDAutoCompatibility.ps1',
  'payload\Resolve-BDAutoTargetProfile.ps1',
  'payload\Sync-BetterDiscordAddons.ps1',
  'payload\addons.manifest.json',
  'payload\BetterDiscordWatchdog\BetterDiscord-Watchdog.ps1',
  'payload\BetterDiscordWatchdog\Install-BetterDiscord-WatchdogTask.ps1',
  'payload\BetterDiscordWatchdog\Remove-BetterDiscord-WatchdogTask.ps1',
  'scripts\Test-Compatibility.ps1',
  'scripts\Test-AddonSync.ps1',
  'docs\RELEASE-NOTES-v1.1.0.md'
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
Test-Condition -Name 'Manifest stable identities' -Passed (@($manifest | Where-Object { [string]::IsNullOrWhiteSpace($_.addon_id) }).Count -eq 0) -Detail 'all entries identified'
Test-Condition -Name 'Manifest source repositories' -Passed (@($manifest | Where-Object { [string]::IsNullOrWhiteSpace($_.source_repo) }).Count -eq 0) -Detail 'all entries source-aware'
Test-Condition -Name 'Manifest downgrade-safe policy' -Passed (@($manifest | Where-Object update_policy -ne 'source-preferred-no-downgrade').Count -eq 0) -Detail 'all entries protected'
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
$buildScript = Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts\Build.ps1') -Raw
$signingDoc = Get-Content -LiteralPath (Join-Path $RepoRoot 'SIGNING.md') -Raw
Test-Condition -Name 'Installer notice page' -Passed ($installerScript -match 'InfoBeforeFile=\.\.\\INSTALL-NOTICE\.txt') -Detail 'configured'
Test-Condition -Name 'Installed legal files' -Passed ($installerScript -match 'THIRD-PARTY-NOTICES\.md' -and $installerScript -match '\.\.\\LICENSE') -Detail 'license and notices included'
Test-Condition -Name 'Installed version file' -Passed ($installerScript -match '\.\.\\VERSION') -Detail 'version copied into app root'
Test-Condition -Name 'Automatic UAC request' -Passed ($installerScript -match 'PrivilegesRequired=admin') -Detail 'configured'
Test-Condition -Name 'Signing guidance' -Passed ($signingDoc -match 'does not remove the Windows User Account Control prompt' -and $signingDoc -match 'Never commit certificate files, private keys') -Detail 'UAC and secret handling documented'

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
$compatibilityScript = Get-Content -LiteralPath (Join-Path $RepoRoot 'payload\Get-BDAutoCompatibility.ps1') -Raw
$syncScript = Get-Content -LiteralPath (Join-Path $RepoRoot 'payload\Sync-BetterDiscordAddons.ps1') -Raw
Test-Condition -Name 'Logon trigger' -Passed ($taskScript -match '<LogonTrigger>') -Detail 'configured'
Test-Condition -Name 'Wake event trigger' -Passed ($taskScript -match 'Power-Troubleshooter' -and $taskScript -match 'EventID=1') -Detail 'configured'
Test-Condition -Name 'No recurring timer' -Passed ($taskScript -notmatch 'RepetitionInterval|MSFT_TaskTimeTrigger|<TimeTrigger>') -Detail 'none'
Test-Condition -Name 'Hidden task execution' -Passed ($taskScript -match '<Hidden>true</Hidden>' -and $taskScript -match '-WindowStyle Hidden') -Detail 'configured'
Test-Condition -Name 'Bundled-first repair CLI' -Passed ($watchdogScript -match 'Get-BdcliForRepair' -and $watchdogScript -match 'Using existing BetterDiscord CLI' -and $watchdogScript -match 'bdcli_checksums\.txt' -and $watchdogScript -match 'Get-FileHash') -Detail 'local first, checksum-verified download fallback'
Test-Condition -Name 'Target profile resolver' -Passed ($profileResolver -match 'running Discord process' -and $profileResolver -match 'interactive Explorer process' -and $profileResolver -match 'only Windows profile with Discord Stable') -Detail 'multi-source detection configured'
Test-Condition -Name 'Discord process-tree shutdown' -Passed ($profileResolver -match 'Get-BDAutoDiscordProcessIds' -and $profileResolver -match 'ParentProcessId' -and $installScript -match 'Get-BDAutoDiscordProcessIds' -and $watchdogScript -match 'Get-BDAutoDiscordProcessIds') -Detail 'hidden child processes included'
Test-Condition -Name 'Explicit profile overrides' -Passed ($installScript -match 'TargetRoamingAppData' -and $watchdogScript -match 'TargetRoamingAppData' -and $taskScript -match 'TargetRoamingAppData') -Detail 'installer, watchdog, and task support overrides'
Test-Condition -Name 'Path-bound CLI install' -Passed ($installScript -match 'install --path \$discordApp\.FullName' -and $watchdogScript -match 'install --path \$stableSignature\.Path') -Detail 'installer and repair target exact Discord app'
Test-Condition -Name 'Saved target state' -Passed ($installScript -match 'target-profile\.json' -and $watchdogScript -match 'target-profile\.json' -and $taskScript -match 'target-profile\.json') -Detail 'shared profile state configured'
Test-Condition -Name 'Original-user setup' -Passed ($installerScript -match 'ExecAsOriginalUser' -and $installerScript -match '-SkipTaskInstall') -Detail 'per-user work avoids elevated AppData'
Test-Condition -Name 'Target-bound task action' -Passed ($taskScript -match '-TargetUserName' -and $taskScript -match '-TargetLocalAppData') -Detail 'scheduled repair remains on Discord user profile'
Test-Condition -Name 'Bundled CLI staging' -Passed ($buildScript -match 'Add-VerifiedBdcliToPayload' -and $buildScript -match 'bdcli_checksums\.txt' -and $buildScript -match 'MyPayloadDir') -Detail 'verified CLI embedded at build time'
Test-Condition -Name 'winget optional at runtime' -Passed ($installScript -notmatch 'winget install' -and $compatibilityScript -match 'WingetPresent') -Detail 'detected but never required'
Test-Condition -Name 'Compatibility preflight' -Passed ($compatibilityScript -match 'CustomWindowsSuspected' -and $compatibilityScript -match 'TaskSchedulerAvailable' -and $installScript -match 'compatibility\.json' -and $watchdogScript -match 'compatibility\.json') -Detail 'stock and reduced-component Windows reported'
Test-Condition -Name 'Graceful task fallback' -Passed ($taskScript -match 'installed-logon-only' -and $taskScript -match 'task-status\.json' -and $installerScript -match 'Scheduled repair automation could not be installed') -Detail 'task failure does not abort core setup'
Test-Condition -Name 'Always-present repair shortcuts' -Passed ($installerScript -match '\{autodesktop\}\\Repair BetterDiscord' -and $installerScript -match '\{group\}\\Repair BetterDiscord' -and $installerScript -match '-RestoreStash') -Detail 'desktop and Start Menu fallback configured'
Test-Condition -Name 'Installer summary' -Passed ($installScript -match 'install-summary\.txt' -and $installerScript -match 'Installation Summary') -Detail 'machine-readable and user-facing results configured'
Test-Condition -Name 'Status artifacts' -Passed ($installScript -match 'installed-version\.json' -and $installScript -match 'BD-AUTO-STATUS\.txt' -and $installerScript -match 'View BD-AUTO Status') -Detail 'version and status outputs configured'
Test-Condition -Name 'Status command' -Passed ($watchdogScript -match '\[switch\]\$Status' -and $watchdogScript -match 'Show-Status') -Detail 'read-only status mode present'
Test-Condition -Name 'Safe duplicate cleanup' -Passed ($installScript -match 'RemoveRecognizedDuplicates' -and $watchdogScript -match 'RemoveRecognizedDuplicates') -Detail 'recognized duplicates removed without pruning unrelated addons'
Test-Condition -Name 'Downgrade-safe addon selection' -Passed ($syncScript -match 'preserved installed newer version' -and $syncScript -match 'source comparison was unknown' -and $syncScript -match 'fallback cache') -Detail 'installed/source/cache versions compared safely'
Test-Condition -Name 'Addon audit mode' -Passed ($watchdogScript -match "Alias\('PluginAudit'\)" -and $watchdogScript -match 'AddonAudit' -and $syncScript -match 'AuditOnly') -Detail 'read-only report command available'
Test-Condition -Name 'Discord update detection' -Passed ($watchdogScript -match 'Discord app path changed since the last successful repair' -and $watchdogScript -match 'Discord app write time changed since the last successful repair') -Detail 'path and write-time drift trigger repair'
Test-Condition -Name 'Precise injection marker' -Passed ($watchdogScript -match 'BetterDiscord\.\{0,160\}data\.\{0,160\}betterdiscord') -Detail 'BetterDiscord data ASAR path required'
Test-Condition -Name 'PowerShell 5.1 manifest enumeration' -Passed ($syncScript -match 'foreach \(\$entry in \$parsedManifest\)' -and $installScript -match 'foreach \(\$entry in \$parsedManifest\)') -Detail 'JSON arrays explicitly enumerated'
Test-Condition -Name 'Non-elevated Discord relaunch' -Passed ($installScript -match 'Shell\.Application' -and $watchdogScript -match 'Shell\.Application') -Detail 'elevated repair delegates launch to Explorer'
Test-Condition -Name 'No hidden UAC prompt' -Passed ($taskScript -match '-NoElevationPrompt' -and $watchdogScript -match 'repair-requires-elevation') -Detail 'scheduled checks defer elevation to manual shortcut'

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

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\Test-Compatibility.ps1')
Test-Condition -Name 'Reduced Windows simulation' -Passed ($LASTEXITCODE -eq 0) -Detail 'custom branding and stripped components degrade safely'

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\Test-AddonSync.ps1')
Test-Condition -Name 'Addon synchronization scenarios' -Passed ($LASTEXITCODE -eq 0) -Detail 'downgrade, upgrade, cache fallback, and unknown-version behavior validated'

if ($failures.Count -gt 0) {
  Write-Host "`nRepository validation failed:"
  $failures | ForEach-Object { Write-Host " - $_" }
  exit 1
}

Write-Host "`nRepository validation passed."
