[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$SkipBdcliDownload,
  [switch]$SkipBetterDiscordInstall,
  [switch]$SkipAddonSync,
  [switch]$SkipTaskInstall,
  [switch]$SkipShortcuts,
  [switch]$NoLaunchDiscord,
  [string]$TargetUserName,
  [string]$TargetRoamingAppData,
  [string]$TargetLocalAppData
)

$ErrorActionPreference = 'Stop'
$InvocationParameters = @{} + $PSBoundParameters
$SourceRoot = Split-Path -Parent $PSCommandPath
$TargetRoot = 'C:\Tools\BD-AUTO'
$VersionPath = Join-Path $SourceRoot 'VERSION'
$PackageVersion = if (Test-Path -LiteralPath $VersionPath) { (Get-Content -LiteralPath $VersionPath -Raw).Trim() } else { '0.0.0' }
$ReleaseUrl = "https://github.com/Drakcain/BD-AUTO/releases/tag/v$PackageVersion"
$LatestReleaseUrl = 'https://github.com/Drakcain/BD-AUTO/releases/latest'
$RepoUrl = 'https://github.com/Drakcain/BD-AUTO'
$ProfileResolverPath = Join-Path $SourceRoot 'Resolve-BDAutoTargetProfile.ps1'
$CompatibilityPath = Join-Path $SourceRoot 'Get-BDAutoCompatibility.ps1'
if (-not (Test-Path -LiteralPath $ProfileResolverPath)) {
  throw "Target profile resolver not found: $ProfileResolverPath"
}
if (-not (Test-Path -LiteralPath $CompatibilityPath)) {
  throw "Compatibility helper not found: $CompatibilityPath"
}
. $ProfileResolverPath
. $CompatibilityPath
$InstallStatus = [ordered]@{
  Version = $PackageVersion
  InstallMode = 'fresh-install'
  CoreInstalled = $false
  InjectionVerified = $false
  ManagedPlugins = 0
  ManagedThemes = 0
  DiscordRelaunched = $false
  ScheduledTask = 'not-attempted'
  ManualRepairShortcut = $false
  ReleaseUrl = $ReleaseUrl
  LatestReleaseUrl = $LatestReleaseUrl
  InstalledAt = $null
  InstallerSourcePath = $SourceRoot
  InstallPath = $TargetRoot
  WindowsVersion = $null
  FailureReason = $null
  LatestLogPath = $null
}

function Write-InstallLog {
  param([string]$Message, [string]$Level = 'INFO')
  $installLogDir = Join-Path $TargetRoot 'logs'
  New-Item -ItemType Directory -Force -Path $installLogDir | Out-Null
  $installLogPath = Join-Path $installLogDir ("installer-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
  $script:InstallStatus.LatestLogPath = $installLogPath
  $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
  Add-Content -LiteralPath $installLogPath -Value $line
  Write-Host $line
}

function Get-ExistingInstalledVersion {
  $installedVersionPath = Join-Path $TargetRoot 'VERSION'
  if (-not (Test-Path -LiteralPath $installedVersionPath)) { return $null }
  $raw = (Get-Content -LiteralPath $installedVersionPath -Raw).Trim()
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  return $raw
}

function Get-InstallMode {
  param([string]$ExistingVersion, [string]$CurrentVersion)

  if ([string]::IsNullOrWhiteSpace($ExistingVersion)) { return 'fresh-install' }
  if ($ExistingVersion -eq $CurrentVersion) { return 'reinstall' }
  return 'update'
}

function Write-InstalledVersionFiles {
  param($Compatibility)

  $runtimeDir = Join-Path $TargetRoot 'runtime'
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
  [System.IO.File]::WriteAllText(
    (Join-Path $TargetRoot 'VERSION'),
    $PackageVersion + [Environment]::NewLine,
    (New-Object System.Text.UTF8Encoding($false))
  )

  $taskStatusPath = Join-Path $runtimeDir 'task-status.json'
  $taskStatus = $null
  if (Test-Path -LiteralPath $taskStatusPath) {
    try { $taskStatus = Get-Content -LiteralPath $taskStatusPath -Raw | ConvertFrom-Json } catch { }
  }

  $manualRepairShortcutInstalled = $InstallStatus.ManualRepairShortcut -or $SkipShortcuts
  $scheduledTaskInstalled = $InstallStatus.ScheduledTask -in @('installed', 'installed-logon-only', 'deferred')
  $installedVersion = [ordered]@{
    version = $PackageVersion
    installed_at = $InstallStatus.InstalledAt
    install_mode = $InstallStatus.InstallMode
    install_completed = $InstallStatus.CoreInstalled
    installer_source_path = $InstallStatus.InstallerSourcePath
    install_path = $TargetRoot
    target_user = $TargetProfile.UserName
    target_roaming_appdata = $TargetProfile.RoamingAppData
    target_local_appdata = $TargetProfile.LocalAppData
    discord_path = $TargetProfile.DiscordRoot
    betterdiscord_path = $TargetProfile.BetterDiscordRoot
    bdcli_path = Get-BdcliPath
    betterdiscord_injection_verified = $InstallStatus.InjectionVerified
    managed_plugins = $InstallStatus.ManagedPlugins
    managed_themes = $InstallStatus.ManagedThemes
    addon_audit_report = (Join-Path $runtimeDir 'addon-audit.json')
    scheduled_task_installed = $scheduledTaskInstalled
    scheduled_task_status = $InstallStatus.ScheduledTask
    scheduled_task_message = if ($taskStatus) { $taskStatus.message } else { $null }
    manual_repair_shortcut_installed = $manualRepairShortcutInstalled
    repo_url = $RepoUrl
    release_url = $ReleaseUrl
    installer_sha256 = $null
    windows_version = $Compatibility.WindowsCaption
    windows_display_version = $Compatibility.WindowsDisplayVersion
    windows_build = $Compatibility.WindowsBuild
    compatibility_mode = if ($Compatibility.CustomWindowsSuspected) { 'custom-windows-detected' } else { 'standard-windows' }
    custom_windows_detected = [bool]$Compatibility.CustomWindowsSuspected
    failure_reason = $InstallStatus.FailureReason
    latest_log_path = $InstallStatus.LatestLogPath
  }
  [System.IO.File]::WriteAllText(
    (Join-Path $runtimeDir 'installed-version.json'),
    ($installedVersion | ConvertTo-Json -Depth 6),
    (New-Object System.Text.UTF8Encoding($false))
  )
}

function Write-StatusText {
  param($Compatibility)

  $taskMessage = switch ($InstallStatus.ScheduledTask) {
    'installed' { 'installed' }
    'installed-logon-only' { 'installed for sign-in only; wake-event support is unavailable' }
    'deferred' { 'setup handled by the elevated installer stage' }
    default { 'unavailable; use the Repair BetterDiscord shortcut after Discord updates' }
  }
  $statusText = @(
    'BD-AUTO Status',
    "Version: $PackageVersion",
    "Installed: $($InstallStatus.InstalledAt)",
    "Install mode: $($InstallStatus.InstallMode)",
    "Install path: $TargetRoot",
    "Target user: $($TargetProfile.UserName)",
    "Discord path: $($TargetProfile.DiscordRoot)",
    "BetterDiscord path: $($TargetProfile.BetterDiscordRoot)",
    "BetterDiscord injection: $(if ($InstallStatus.InjectionVerified) { 'verified' } else { 'not verified' })",
    "Plugins: $($InstallStatus.ManagedPlugins)/16",
    "Themes: $($InstallStatus.ManagedThemes)/2",
    "Scheduled task: $taskMessage",
    "Manual repair shortcut: $(if ($InstallStatus.ManualRepairShortcut -or $SkipShortcuts) { 'installed' } else { 'not installed' })",
    "Latest log: $($InstallStatus.LatestLogPath)",
    "Release: $ReleaseUrl",
    "Latest releases: $LatestReleaseUrl"
  )
  if ($InstallStatus.FailureReason) {
    $statusText += "Failure reason: $($InstallStatus.FailureReason)"
  }
  [System.IO.File]::WriteAllText(
    (Join-Path $TargetRoot 'BD-AUTO-STATUS.txt'),
    (($statusText -join [Environment]::NewLine) + [Environment]::NewLine),
    (New-Object System.Text.UTF8Encoding($false))
  )
}

function Invoke-SelfElevate {
  param($ResolvedProfile)

  $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
  foreach ($entry in $script:InvocationParameters.GetEnumerator()) {
    if ($entry.Key -in @('TargetUserName', 'TargetRoamingAppData', 'TargetLocalAppData')) { continue }
    if ($entry.Value -is [bool]) {
      if ($entry.Value) { $argList += "-$($entry.Key)" }
    } else {
      $argList += "-$($entry.Key)"
      $argList += "$($entry.Value)"
    }
  }
  $argList += '-TargetUserName', $ResolvedProfile.UserName
  $argList += '-TargetRoamingAppData', $ResolvedProfile.RoamingAppData
  $argList += '-TargetLocalAppData', $ResolvedProfile.LocalAppData
  Write-Host 'Elevation required. Relaunching installer as administrator...'
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList | Out-Null
  exit
}

function Get-BdcliPath {
  $targetBundle = Join-Path $TargetRoot 'bin\bdcli.exe'
  if (Test-Path -LiteralPath $targetBundle) { return $targetBundle }

  $cmd = Get-Command bdcli -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) { return $cmd.Source }

  $winGetPackages = Join-Path $TargetProfile.LocalAppData 'Microsoft\WinGet\Packages'
  if (Test-Path -LiteralPath $winGetPackages) {
    $candidate = Get-ChildItem -Path $winGetPackages -Filter 'betterdiscord.cli*' -Directory -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($candidate) {
      $exe = Join-Path $candidate.FullName 'bdcli.exe'
      if (Test-Path -LiteralPath $exe) { return $exe }
    }
  }

  $links = Join-Path $TargetProfile.LocalAppData 'Microsoft\WinGet\Links\bdcli.exe'
  if (Test-Path -LiteralPath $links) { return $links }

  return $null
}

function Copy-Bundle {
  param([string]$SourceRoot, [string]$DestinationRoot)

  $src = (Resolve-Path -LiteralPath $SourceRoot).Path.TrimEnd('\')
  $dst = (New-Item -ItemType Directory -Force -Path $DestinationRoot).FullName.TrimEnd('\')
  if ($src -ieq $dst) {
    Write-InstallLog "Source and destination are the same ($src); skipping file copy."
    return
  }

  Write-InstallLog "Copying BD-AUTO bundle from $src to $dst"
  $args = @($src, $dst, '/E', '/XD', 'logs', 'backups', '/XF', 'state.json')
  & robocopy @args | Out-Null
  $code = $LASTEXITCODE
  if ($code -ge 8) {
    throw "Robocopy failed with exit code $code"
  }
  Write-InstallLog "Bundle copy completed with robocopy exit code $code"
}

function Ensure-BdcliBinary {
  $existingBdcli = Get-BdcliPath

  if ($existingBdcli -and $existingBdcli -ieq (Join-Path $TargetRoot 'bin\bdcli.exe')) {
    Write-InstallLog "Using bundled BetterDiscord CLI: $existingBdcli"
    return
  }

  if ($SkipBdcliDownload) {
    if ($existingBdcli) {
      Write-InstallLog "BetterDiscord CLI refresh skipped; using existing binary: $existingBdcli" 'WARN'
    } else {
      Write-InstallLog 'bdcli missing and download was skipped.' 'WARN'
    }
    return
  }

  $binDir = Join-Path $TargetRoot 'bin'
  New-Item -ItemType Directory -Force -Path $binDir | Out-Null

  $tempRoot = $null
  $zipPath = $null
  $checksumPath = $null
  try {
    $headers = @{ 'User-Agent' = 'BD-AUTO Installer' }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/BetterDiscord/cli/releases/latest' -Headers $headers
    $asset = $release.assets | Where-Object { $_.name -match '(?i)windows.*amd64.*\.zip$' -or $_.name -match '(?i)bdcli_.*_windows_amd64\.zip$' } | Select-Object -First 1
    if (-not $asset) { throw 'No Windows amd64 release asset found.' }
    $checksumAsset = $release.assets | Where-Object { $_.name -eq 'bdcli_checksums.txt' } | Select-Object -First 1
    if (-not $checksumAsset) { throw 'BetterDiscord CLI checksum asset was not found.' }

    $tempRoot = Join-Path $env:TEMP ("bdcli-{0}" -f $release.tag_name)
    $zipPath = Join-Path $env:TEMP ("bdcli-{0}.zip" -f $release.tag_name)
    $checksumPath = Join-Path $env:TEMP ("bdcli-checksums-{0}.txt" -f $release.tag_name)
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $checksumPath -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

    Write-InstallLog "Downloading BetterDiscord CLI $($release.tag_name)"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
    Invoke-WebRequest -Uri $checksumAsset.browser_download_url -OutFile $checksumPath

    $checksumLine = Get-Content -LiteralPath $checksumPath | Where-Object { $_ -match [regex]::Escape($asset.name) } | Select-Object -First 1
    if (-not $checksumLine -or $checksumLine -notmatch '^(?<hash>[A-Fa-f0-9]{64})\s+') {
      throw "Published checksum was not found for $($asset.name)."
    }
    $expectedHash = $Matches.hash.ToUpperInvariant()
    $actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -ne $expectedHash) {
      throw "BetterDiscord CLI checksum mismatch. Expected $expectedHash, received $actualHash."
    }

    Expand-Archive -LiteralPath $zipPath -DestinationPath $tempRoot -Force

    $bdcliExe = Get-ChildItem -Path $tempRoot -Recurse -Filter 'bdcli.exe' -File | Select-Object -First 1
    if (-not $bdcliExe) { throw 'bdcli.exe was not found after extraction.' }

    Copy-Item -LiteralPath $bdcliExe.FullName -Destination (Join-Path $binDir 'bdcli.exe') -Force
    Write-InstallLog "Installed checksum-verified bdcli to $(Join-Path $binDir 'bdcli.exe')"
  } catch {
    Write-InstallLog "GitHub download failed: $_" 'WARN'
    if ($existingBdcli -and (Test-Path -LiteralPath $existingBdcli)) {
      Write-InstallLog "Continuing with existing BetterDiscord CLI: $existingBdcli" 'WARN'
      return
    }

    throw 'A checksum-verified BetterDiscord CLI could not be prepared. winget is intentionally not required or invoked.'
  } finally {
    if ($tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
    if ($zipPath) { Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue }
    if ($checksumPath) { Remove-Item -LiteralPath $checksumPath -Force -ErrorAction SilentlyContinue }
  }
}

function Install-BetterDiscord {
  if ($SkipBetterDiscordInstall) {
    Write-InstallLog 'BetterDiscord install skipped.'
    return
  }

  $bdcli = Get-BdcliPath
  if (-not $bdcli) {
    throw 'BetterDiscord CLI not available after setup.'
  }

  function Stop-DiscordForInstall {
    param([int]$GracefulTimeoutSeconds = 3, [int]$ForceAttempts = 5)

    $ids = @(Get-BDAutoDiscordProcessIds -Profile $TargetProfile | Sort-Object -Unique)
    if ($ids.Count -eq 0) { return }

    $processes = @($ids | ForEach-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue } | Where-Object { $_ })
    foreach ($process in $processes) {
      try { [void]$process.CloseMainWindow() } catch { }
    }

    $deadline = (Get-Date).AddSeconds($GracefulTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
      $remainingIds = @(Get-BDAutoDiscordProcessIds -Profile $TargetProfile | Sort-Object -Unique)
      if ($remainingIds.Count -eq 0) { return }
      Start-Sleep -Milliseconds 500
    }

    for ($attempt = 1; $attempt -le $ForceAttempts; $attempt++) {
      $remainingIds = @(Get-BDAutoDiscordProcessIds -Profile $TargetProfile | Sort-Object -Unique)
      if ($remainingIds.Count -eq 0) { return }
      foreach ($id in $remainingIds) {
        try {
          Stop-Process -Id $id -Force -ErrorAction Stop
        } catch {
          try { & taskkill.exe /PID $id /T /F 2>&1 | Out-Null } catch { }
        }
      }
      Start-Sleep -Seconds 1
    }

    try { & taskkill.exe /IM Discord.exe /F /T 2>&1 | Out-Null } catch { }
    try { & taskkill.exe /IM Update.exe /F /T 2>&1 | Out-Null } catch { }
    Start-Sleep -Seconds 2

    $remainingIds = @(Get-BDAutoDiscordProcessIds -Profile $TargetProfile | Sort-Object -Unique)
    if ($remainingIds.Count -gt 0) {
      throw "Could not stop all Discord processes: $($remainingIds -join ', ')"
    }
  }

  $discordRoot = $TargetProfile.DiscordRoot
  $discordProcessIds = @(Get-BDAutoDiscordProcessIds -Profile $TargetProfile | Sort-Object -Unique)
  if ($discordProcessIds.Count -gt 0) {
    Write-InstallLog ('Stopping Discord before BetterDiscord install: {0}' -f ($discordProcessIds -join ', '))
    Stop-DiscordForInstall
  }

  $discordApp = Get-ChildItem -LiteralPath $discordRoot -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'Discord.exe') } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $discordApp) {
    throw "Discord Stable installation was not found for $($TargetProfile.UserName): $discordRoot"
  }

  Write-InstallLog "Running BetterDiscord CLI install via $bdcli against $($discordApp.FullName)"
  & $bdcli install --path $discordApp.FullName 2>&1 | ForEach-Object { Write-Host $_ }
  $code = $LASTEXITCODE
  Write-InstallLog "bdcli install exit code: $code"
  if ($code -ne 0) {
    throw "bdcli install failed with exit code $code"
  }

  $coreIndex = Join-Path $discordApp.FullName 'modules\discord_desktop_core-1\discord_desktop_core\index.js'
  $injectionVerified = $false
  if (Test-Path -LiteralPath $coreIndex) {
    $coreText = Get-Content -LiteralPath $coreIndex -Raw
    $injectionVerified = (
      $coreText -match '(?is)BetterDiscord.{0,160}data.{0,160}betterdiscord\.asar' -and
      $coreText -match "(?i)BetterDiscord'?s Injection Script"
    )
  }
  $script:InstallStatus.InjectionVerified = $injectionVerified
  if (-not $injectionVerified) {
    throw "BetterDiscord CLI completed, but injection was not verified in $coreIndex"
  }
  Write-InstallLog "BetterDiscord injection verified: $coreIndex"
}

function Start-Discord {
  if ($NoLaunchDiscord) {
    Write-InstallLog 'Discord launch skipped.'
    return $false
  }

  if (Get-Process -Name Discord -ErrorAction SilentlyContinue) {
    Write-InstallLog 'Discord is already running.'
    return $true
  }

  $updateExe = Join-Path $TargetProfile.DiscordRoot 'Update.exe'
  if (-not (Test-Path -LiteralPath $updateExe)) {
    throw "Discord launcher not found: $updateExe"
  }

  Write-InstallLog 'Launching Discord.'
  if (Test-BDAutoAdministrator) {
    try {
      $shell = New-Object -ComObject Shell.Application
      $shell.ShellExecute($updateExe, '--processStart Discord.exe', $TargetProfile.DiscordRoot, 'open', 1)
      Write-InstallLog 'Discord launch delegated to the interactive Explorer shell to avoid an elevated Discord process.'
    } catch {
      Write-InstallLog "Explorer-shell launch failed; using direct launch. $_" 'WARN'
      Start-Process -FilePath $updateExe -ArgumentList '--processStart Discord.exe' | Out-Null
    }
  } else {
    Start-Process -FilePath $updateExe -ArgumentList '--processStart Discord.exe' | Out-Null
  }
  $deadline = (Get-Date).AddSeconds(30)
  while ((Get-Date) -lt $deadline) {
    if (Get-Process -Name Discord -ErrorAction SilentlyContinue) {
      Write-InstallLog 'Discord launched successfully.'
      return $true
    }
    Start-Sleep -Seconds 2
  }
  throw 'Discord did not start within 30 seconds.'
}

function Install-WatchdogTask {
  if ($SkipTaskInstall) {
    $existingTaskStatusPath = Join-Path $TargetRoot 'runtime\task-status.json'
    $existingTaskStatus = $null
    if (Test-Path -LiteralPath $existingTaskStatusPath) {
      try { $existingTaskStatus = Get-Content -LiteralPath $existingTaskStatusPath -Raw | ConvertFrom-Json } catch { }
    }
    if ($existingTaskStatus -and $existingTaskStatus.status -in @('installed', 'installed-logon-only')) {
      $script:InstallStatus.ScheduledTask = $existingTaskStatus.status
      Write-InstallLog "Scheduled task install skipped; preserving existing status: $($existingTaskStatus.status)."
    } else {
      Write-InstallLog 'Scheduled task install skipped; elevated installer stage will register it.'
      $script:InstallStatus.ScheduledTask = 'deferred'
    }
    return $true
  }

  $taskScript = Join-Path $TargetRoot 'BetterDiscordWatchdog\Install-BetterDiscord-WatchdogTask.ps1'
  if (-not (Test-Path -LiteralPath $taskScript)) {
    Write-InstallLog "Task installer not found: $taskScript" 'WARN'
    $script:InstallStatus.ScheduledTask = 'unavailable'
    return $false
  }

  Write-InstallLog 'Installing BetterDiscord watchdog scheduled task.'
  try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $taskScript `
      -TargetUserName $TargetProfile.UserName `
      -TargetUserSid $TargetProfile.UserSid `
      -TargetRoamingAppData $TargetProfile.RoamingAppData `
      -TargetLocalAppData $TargetProfile.LocalAppData | Out-Host
    if ($LASTEXITCODE -ne 0) {
      throw "Scheduled task installer failed with exit code $LASTEXITCODE"
    }
    $script:InstallStatus.ScheduledTask = 'installed'
    return $true
  } catch {
    Write-InstallLog "Scheduled task unavailable; manual repair shortcuts remain available. $_" 'WARN'
    $script:InstallStatus.ScheduledTask = 'unavailable'
    return $false
  }
}

function New-DesktopShortcut {
  if ($SkipShortcuts) {
    $script:InstallStatus.ManualRepairShortcut = $true
    Write-InstallLog 'Shortcut creation skipped.'
    return
  }

  $shortcutDir = Join-Path $TargetProfile.ProfileRoot 'Desktop'
  if ([string]::IsNullOrWhiteSpace($shortcutDir)) {
    Write-InstallLog 'Desktop path not found; skipping shortcut creation.' 'WARN'
    return
  }

  $watchdogScript = Join-Path $TargetRoot 'BetterDiscordWatchdog\BetterDiscord-Watchdog.ps1'
  $shortcutPath = Join-Path $shortcutDir 'Repair BetterDiscord.lnk'
  $wsh = New-Object -ComObject WScript.Shell
  $shortcut = $wsh.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = 'powershell.exe'
  $shortcut.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -ForceRepair -RestoreStash -ReopenDiscord' -f $watchdogScript)
  $shortcut.WorkingDirectory = $TargetRoot
  $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,46"
  $shortcut.Description = 'Repair and reopen BetterDiscord'
  $shortcut.Save()
  $script:InstallStatus.ManualRepairShortcut = $true
  Write-InstallLog "Desktop shortcut created: $shortcutPath"
}

function Sync-AddonManifest {
  if ($SkipAddonSync) {
    Write-InstallLog 'Addon sync skipped.'
    return
  }

  $syncScript = Join-Path $TargetRoot 'Sync-BetterDiscordAddons.ps1'
  $manifestPath = Join-Path $TargetRoot 'addons.manifest.json'
  if (-not (Test-Path -LiteralPath $syncScript)) { throw "Addon sync script not found: $syncScript" }

  Write-InstallLog "Synchronizing curated BetterDiscord addons to $($TargetProfile.BetterDiscordRoot)."
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $syncScript `
    -ManifestPath $manifestPath `
    -ActiveRoot $TargetProfile.BetterDiscordRoot `
    -CacheRoot (Join-Path $TargetRoot 'BetterDiscord') `
    -BackupRoot (Join-Path $TargetRoot 'runtime\backups\addon-sync') `
    -ReportPath (Join-Path $TargetRoot 'runtime\addon-audit.json') `
    -RemoveRecognizedDuplicates | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "Addon sync failed with exit code $LASTEXITCODE"
  }

  $parsedManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $manifest = @()
  foreach ($entry in $parsedManifest) {
    if ($entry.enabled) { $manifest += $entry }
  }
  $pluginCount = @($manifest | Where-Object kind -eq 'plugin' | Where-Object {
    Test-Path -LiteralPath (Join-Path (Join-Path $TargetProfile.BetterDiscordRoot 'plugins') $_.file_name)
  }).Count
  $themeCount = @($manifest | Where-Object kind -eq 'theme' | Where-Object {
    Test-Path -LiteralPath (Join-Path (Join-Path $TargetProfile.BetterDiscordRoot 'themes') $_.file_name)
  }).Count
  $script:InstallStatus.ManagedPlugins = $pluginCount
  $script:InstallStatus.ManagedThemes = $themeCount
  Write-InstallLog "Managed addon verification: plugins=$pluginCount, themes=$themeCount, path=$($TargetProfile.BetterDiscordRoot)"
  if ($pluginCount -ne 16 -or $themeCount -ne 2) {
    throw "Managed addon verification failed. Expected plugins=16/themes=2; found plugins=$pluginCount/themes=$themeCount."
  }
}

function Save-InstallSummary {
  param($Compatibility)

  $runtimeDir = Join-Path $TargetRoot 'runtime'
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
  $customNote = if ($Compatibility.CustomWindowsSuspected) {
    'WARNING: Customized or stripped Windows indicators were detected. Core repair is installed; scheduled automation depends on enabled Windows components.'
  } else {
    'No strong customized/stripped Windows indicators were detected.'
  }
  $taskLine = switch ($InstallStatus.ScheduledTask) {
    'installed' { 'Scheduled task: installed' }
    'deferred' { 'Scheduled task: setup handled by the elevated installer stage' }
    default { 'Scheduled task: unavailable; use the Repair BetterDiscord shortcut after Discord updates' }
  }
  $summary = @(
    "BD-AUTO installation summary",
    "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "BD-AUTO version: $PackageVersion",
    "Release: $ReleaseUrl",
    '',
    "Install mode: $(switch ($InstallStatus.InstallMode) { 'update' { "Updating BD-AUTO from $(Get-ExistingInstalledVersion) to $PackageVersion" } 'reinstall' { "Reinstalling/repairing BD-AUTO v$PackageVersion" } default { "Fresh install of BD-AUTO v$PackageVersion" } })",
    "Core installation: $(if ($InstallStatus.CoreInstalled) { 'successful' } else { 'incomplete' })",
    "BetterDiscord injection: $(if ($InstallStatus.InjectionVerified) { 'verified' } else { 'not verified' })",
    "Managed plugins: $($InstallStatus.ManagedPlugins)/16",
    "Managed themes: $($InstallStatus.ManagedThemes)/2",
    "Discord running after setup: $($InstallStatus.DiscordRelaunched)",
    $taskLine,
    "Manual repair shortcut: $(if ($InstallStatus.ManualRepairShortcut -or $SkipShortcuts) { 'installed by setup' } else { 'not created' })",
    '',
    "Windows: $($Compatibility.WindowsCaption) $($Compatibility.WindowsDisplayVersion) build $($Compatibility.WindowsBuild)",
    "PowerShell: $($Compatibility.PowerShellVersion)",
    "Target user: $($TargetProfile.UserName)",
    "Install path: $TargetRoot",
    "Discord: $($TargetProfile.DiscordRoot)",
    "BetterDiscord: $($TargetProfile.BetterDiscordRoot)",
    "Bundled bdcli: $($Compatibility.BundledBdcliPresent)",
    "winget required: False (detected: $($Compatibility.WingetPresent))",
    "Task Scheduler available: $($Compatibility.TaskSchedulerAvailable)",
    $customNote,
    '',
    "Status file: $TargetRoot\BD-AUTO-STATUS.txt",
    "Installed version JSON: $TargetRoot\runtime\installed-version.json",
    "Addon audit JSON: $TargetRoot\runtime\addon-audit.json",
    "Logs: $TargetRoot\logs and $TargetRoot\runtime\logs",
    'Manual fallback: run the Repair BetterDiscord desktop or Start Menu shortcut.'
  ) -join [Environment]::NewLine
  [System.IO.File]::WriteAllText(
    (Join-Path $runtimeDir 'install-summary.txt'),
    $summary + [Environment]::NewLine,
    (New-Object System.Text.UTF8Encoding($false))
  )
  [System.IO.File]::WriteAllText(
    (Join-Path $runtimeDir 'install-result.json'),
    ($InstallStatus | ConvertTo-Json -Depth 4),
    (New-Object System.Text.UTF8Encoding($false))
  )
}

function Save-TargetProfileState {
  $runtimeDir = Join-Path $TargetRoot 'runtime'
  New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
  $statePath = Join-Path $runtimeDir 'target-profile.json'
  $profileState = [ordered]@{
    user_name = $TargetProfile.UserName
    user_sid = $TargetProfile.UserSid
    profile_root = $TargetProfile.ProfileRoot
    roaming_app_data = $TargetProfile.RoamingAppData
    local_app_data = $TargetProfile.LocalAppData
    betterdiscord_root = $TargetProfile.BetterDiscordRoot
    discord_root = $TargetProfile.DiscordRoot
    detection_source = $TargetProfile.DetectionSource
    saved_at = (Get-Date).ToString('o')
  }
  [System.IO.File]::WriteAllText(
    $statePath,
    ($profileState | ConvertTo-Json -Depth 4),
    (New-Object System.Text.UTF8Encoding($false))
  )
  Write-InstallLog "Saved target profile state: $statePath"
}

$TargetProfile = Resolve-BDAutoTargetProfile `
  -TargetUserName $TargetUserName `
  -TargetRoamingAppData $TargetRoamingAppData `
  -TargetLocalAppData $TargetLocalAppData
$existingInstalledVersion = Get-ExistingInstalledVersion
$InstallStatus.InstallMode = Get-InstallMode -ExistingVersion $existingInstalledVersion -CurrentVersion $PackageVersion

if (-not $DryRun -and -not $SkipTaskInstall -and -not (Test-BDAutoAdministrator)) {
  Invoke-SelfElevate -ResolvedProfile $TargetProfile
}

New-Item -ItemType Directory -Force -Path $TargetRoot | Out-Null
Write-InstallLog "Starting BD-AUTO install from $SourceRoot to $TargetRoot"
Write-InstallLog "BD-AUTO version: $PackageVersion"
Write-InstallLog "Release URL: $ReleaseUrl"
Write-InstallLog ("Install mode: {0}" -f $(switch ($InstallStatus.InstallMode) { 'update' { "Updating BD-AUTO from $existingInstalledVersion to $PackageVersion" } 'reinstall' { "Reinstalling/repairing BD-AUTO v$PackageVersion" } default { "Fresh install of BD-AUTO v$PackageVersion" } }))
Write-BDAutoTargetProfileLog -Profile $TargetProfile -WriteLog ${function:Write-InstallLog}

if (-not $DryRun) {
  $Compatibility = $null
  try {
    Copy-Bundle -SourceRoot $SourceRoot -DestinationRoot $TargetRoot
    New-Item -ItemType Directory -Force -Path (Join-Path $TargetRoot 'logs'), (Join-Path $TargetRoot 'runtime'), (Join-Path $TargetRoot 'bin') | Out-Null
    $Compatibility = Get-BDAutoCompatibilityReport -TargetProfile $TargetProfile -RootPath $TargetRoot
    $InstallStatus.WindowsVersion = "$($Compatibility.WindowsCaption) $($Compatibility.WindowsDisplayVersion) build $($Compatibility.WindowsBuild)"
    Write-BDAutoCompatibilityLog -Report $Compatibility -WriteLog ${function:Write-InstallLog}
    Save-BDAutoCompatibilityReport -Report $Compatibility -Path (Join-Path $TargetRoot 'runtime\compatibility.json')
    Ensure-BdcliBinary
    Install-BetterDiscord
    Sync-AddonManifest
    Save-TargetProfileState
    [void](Install-WatchdogTask)
    New-DesktopShortcut
    $InstallStatus.DiscordRelaunched = [bool](Start-Discord)
    $InstallStatus.CoreInstalled = $true
    $InstallStatus.InstalledAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Write-InstalledVersionFiles -Compatibility $Compatibility
    Write-StatusText -Compatibility $Compatibility
    Save-InstallSummary -Compatibility $Compatibility
    Write-InstallLog 'Install completed successfully.'
  } catch {
    Write-InstallLog "Install failed: $_" 'ERROR'
    $InstallStatus.FailureReason = $_.Exception.Message
    if (-not $NoLaunchDiscord) {
      try {
        $InstallStatus.DiscordRelaunched = [bool](Start-Discord)
      } catch {
        Write-InstallLog "Discord recovery launch failed: $_" 'ERROR'
      }
    }
    if ($Compatibility) {
      if (-not $InstallStatus.InstalledAt) { $InstallStatus.InstalledAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
      Write-InstalledVersionFiles -Compatibility $Compatibility
      Write-StatusText -Compatibility $Compatibility
      Save-InstallSummary -Compatibility $Compatibility
    }
    throw
  }
} else {
  $Compatibility = Get-BDAutoCompatibilityReport -TargetProfile $TargetProfile -RootPath $SourceRoot
  Write-BDAutoCompatibilityLog -Report $Compatibility -WriteLog ${function:Write-InstallLog}
  Write-InstallLog 'DryRun enabled: bundle copy, CLI download, BetterDiscord install, addon sync, task install, shortcut creation, and Discord launch were skipped.'
}
