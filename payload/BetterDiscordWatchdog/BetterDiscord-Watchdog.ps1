[CmdletBinding()]
param(
  [switch]$Status,
  [switch]$CheckDiscordUpdateState,
  [Alias('PluginAudit')]
  [switch]$AddonAudit,
  [switch]$DryRun,
  [switch]$ForceRepair,
  [switch]$RepairAfterDiscordUpdate,
  [switch]$MonitorDiscordUpdate,
  [switch]$ReopenDiscord,
  [switch]$NoReopenDiscord,
  [switch]$RestoreStash,
  [switch]$NoElevationPrompt,
  [switch]$ElevatedRepair,
  [switch]$WaitForDiscord,
  [int]$StartupDelaySeconds = 0,
  [int]$MonitorTimeoutMinutes = 10,
  [int]$DiscordWaitTimeoutSeconds = 300,
  [int]$DiscordStabilizeSeconds = 10,
  [int]$DiscordStabilizePollSeconds = 2,
  [int]$UpdateQuietSeconds = 15,
  [int]$BackupRetentionCount = 3,
  [string]$TargetUserName,
  [string]$TargetRoamingAppData,
  [string]$TargetLocalAppData
)

$ErrorActionPreference = 'Stop'

$BaseDir = $PSScriptRoot
$RootDir = Split-Path -Parent $BaseDir
$SourceRepoRoot = Split-Path -Parent $RootDir
$RunningFromSourceRepo = (
  (Split-Path -Leaf $RootDir) -eq 'payload' -and
  (Test-Path -LiteralPath (Join-Path $SourceRepoRoot '.git')) -and
  (Test-Path -LiteralPath (Join-Path $SourceRepoRoot 'scripts\Test-Repo.ps1'))
)
$ProfileResolverPath = Join-Path $RootDir 'Resolve-BDAutoTargetProfile.ps1'
$CompatibilityPath = Join-Path $RootDir 'Get-BDAutoCompatibility.ps1'
if (-not (Test-Path -LiteralPath $ProfileResolverPath)) {
  throw "Target profile resolver not found: $ProfileResolverPath"
}
if (-not (Test-Path -LiteralPath $CompatibilityPath)) {
  throw "Compatibility helper not found: $CompatibilityPath"
}
. $ProfileResolverPath
. $CompatibilityPath
$RuntimeContainerRoot = if ($RunningFromSourceRepo) {
  Join-Path $env:TEMP ("bd-auto-source-watchdog-{0}" -f [Environment]::UserName)
} else {
  $RootDir
}
$SavedProfilePath = Join-Path $RootDir 'runtime\target-profile.json'
if (
  (Test-Path -LiteralPath $SavedProfilePath) -and
  -not $TargetUserName -and
  -not $TargetRoamingAppData -and
  -not $TargetLocalAppData
) {
  $savedProfile = Get-Content -LiteralPath $SavedProfilePath -Raw | ConvertFrom-Json
  $TargetUserName = $savedProfile.user_name
  $TargetRoamingAppData = $savedProfile.roaming_app_data
  $TargetLocalAppData = $savedProfile.local_app_data
}
$TargetProfile = Resolve-BDAutoTargetProfile `
  -TargetUserName $TargetUserName `
  -TargetRoamingAppData $TargetRoamingAppData `
  -TargetLocalAppData $TargetLocalAppData

$RuntimeRoot = Join-Path $RuntimeContainerRoot 'runtime'
$LogDir = Join-Path $RuntimeRoot 'logs'
$BackupRoot = Join-Path $RuntimeRoot 'backups'
$StatePath = Join-Path $RuntimeRoot 'state.json'
$ManifestPath = Join-Path $RootDir 'addons.manifest.json'
$AddonSyncPath = Join-Path $RootDir 'Sync-BetterDiscordAddons.ps1'
$AddonCacheRoot = Join-Path $RootDir 'BetterDiscord'
$AddonReportPath = Join-Path $RuntimeRoot 'addon-audit.json'
$VersionFilePath = if ($RunningFromSourceRepo) {
  Join-Path $SourceRepoRoot 'VERSION'
} else {
  Join-Path $RootDir 'VERSION'
}
$InstalledVersionPath = Join-Path $RuntimeRoot 'installed-version.json'
$ReleaseUrl = $null
$DiscordRoot = $TargetProfile.DiscordRoot
$ActiveBDRoot = $TargetProfile.BetterDiscordRoot
$ActivePlugins = Join-Path $ActiveBDRoot 'plugins'
$ActiveThemes = Join-Path $ActiveBDRoot 'themes'
$ActiveData = Join-Path $ActiveBDRoot 'data'

New-Item -ItemType Directory -Force -Path $RuntimeRoot, $LogDir, $BackupRoot | Out-Null
$LogPath = Join-Path $LogDir ("watchdog-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))

function Get-BDAutoVersion {
  if (Test-Path -LiteralPath $VersionFilePath) {
    return (Get-Content -LiteralPath $VersionFilePath -Raw).Trim()
  }
  return 'unknown'
}

function Write-Log {
  param([string]$Message, [string]$Level = 'INFO')
  $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
  Add-Content -LiteralPath $LogPath -Value $line
  Write-Host $line
}

function Get-ScheduledTaskStatus {
  $taskStatusPath = Join-Path $RuntimeRoot 'task-status.json'
  if (-not (Test-Path -LiteralPath $taskStatusPath)) {
    return [pscustomobject]@{
      status = 'unknown'
      message = 'task status file not found'
    }
  }
  try {
    return Get-Content -LiteralPath $taskStatusPath -Raw | ConvertFrom-Json
  } catch {
    return [pscustomobject]@{
      status = 'unknown'
      message = 'task status file could not be parsed'
    }
  }
}

function Show-Status {
  $version = Get-BDAutoVersion
  $releaseUrl = "https://github.com/Drakcain/BD-AUTO/releases/tag/v$version"
  $installedVersion = $null
  if (Test-Path -LiteralPath $InstalledVersionPath) {
    try { $installedVersion = Get-Content -LiteralPath $InstalledVersionPath -Raw | ConvertFrom-Json } catch { }
  }
  $taskStatus = Get-ScheduledTaskStatus
  $workflowState = Get-DiscordWorkflowState -ExistingState $state
  $discordApp = Get-DiscordApp
  $discordAppPath = if ($discordApp) { $discordApp.FullName } else { $null }
  $injectionInstalled = if ($discordAppPath) { Test-BetterDiscordInjection -DiscordAppPath $discordAppPath } else { $false }
  $latestLog = Get-ChildItem -LiteralPath $LogDir -File -Filter 'watchdog-*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  @(
    "BD-AUTO installed version: $version"
    "Install path: $RootDir"
    "Target user: $($TargetProfile.UserName)"
    "Discord path: $DiscordRoot"
    "BetterDiscord path: $ActiveBDRoot"
    "Discord stable state: $($workflowState.stable_channel.install_state)"
    "Discord stable running app: $(if ($workflowState.stable_channel.running_app_version) { $workflowState.stable_channel.running_app_version } else { 'none' })"
    "Discord stable latest app: $(if ($workflowState.stable_channel.latest_app_version) { $workflowState.stable_channel.latest_app_version } else { 'none' })"
    "Discord pending update: $($workflowState.stable_channel.pending_update)"
    "BetterDiscord injection: $(if ($injectionInstalled) { 'verified' } else { 'not verified' })"
    "Plugins: $(Get-Count -Path $ActivePlugins -Filter '*.plugin.js')"
    "Themes: $(Get-Count -Path $ActiveThemes -Filter '*.theme.css')"
    "Scheduled task: $($taskStatus.status)"
    "Scheduled task detail: $($taskStatus.message)"
    "Latest log path: $(if ($latestLog) { $latestLog.FullName } else { $LogPath })"
    "Addon audit path: $AddonReportPath"
    "Release URL: $releaseUrl"
    "Installed-at: $(if ($installedVersion) { $installedVersion.installed_at } else { 'unknown' })"
  ) | ForEach-Object { Write-Host $_ }
}

function Get-Count {
  param([string]$Path, [string]$Filter = '*')
  if (-not (Test-Path -LiteralPath $Path)) { return 0 }
  return (Get-ChildItem -LiteralPath $Path -File -Filter $Filter -ErrorAction SilentlyContinue | Measure-Object).Count
}

function Load-State {
  if (-not (Test-Path -LiteralPath $StatePath)) { return @{} }
  try {
    $raw = Get-Content -LiteralPath $StatePath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
    $obj = $raw | ConvertFrom-Json
    $state = @{}
    $obj.psobject.Properties | ForEach-Object { $state[$_.Name] = $_.Value }
    return $state
  } catch {
    Write-Log "State read failed; starting with empty state. $_" 'WARN'
    return @{}
  }
}

function Save-State {
  param([hashtable]$State)
  $json = $State | ConvertTo-Json -Depth 8
  $tempPath = "$StatePath.tmp-$([guid]::NewGuid().ToString('N'))"
  try {
    [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tempPath -Destination $StatePath -Force
  } finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
  }
}

function Get-DiscordProcesses {
  $ids = @(Get-BDAutoDiscordProcessIds -Profile $TargetProfile)
  return @($ids | ForEach-Object {
    Get-Process -Id $_ -ErrorAction SilentlyContinue
  } | Where-Object { $_ })
}

function Get-DiscordApp {
  $running = Get-DiscordProcesses |
    Where-Object { $_.Path -and (Test-Path -LiteralPath $_.Path) } |
    Select-Object -First 1
  if ($running) {
    return Get-Item -LiteralPath (Split-Path -Parent $running.Path)
  }

  if (-not (Test-Path -LiteralPath $DiscordRoot)) { return $null }
  return Get-ChildItem -LiteralPath $DiscordRoot -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'Discord.exe') } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Get-DiscordAppSignature {
  $app = Get-DiscordApp
  if (-not $app) { return $null }
  return [pscustomobject]@{
    Path = $app.FullName
    Version = ($app.Name -replace '^app-', '')
    WriteTime = $app.LastWriteTime.ToString('o')
  }
}

function Get-DiscordUpdaterProcesses {
  $processes = @()
  try {
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='Update.exe'" -ErrorAction Stop)
  } catch {
    $processes = @(Get-Process Update -ErrorAction SilentlyContinue | ForEach-Object {
      [pscustomobject]@{
        ProcessId = $_.Id
        ExecutablePath = try { $_.Path } catch { $null }
      }
    })
  }

  return @($processes | Where-Object {
    $_.ExecutablePath -and
    $_.ExecutablePath.StartsWith($DiscordRoot, [System.StringComparison]::OrdinalIgnoreCase)
  })
}

function Get-DiscordAppDirectories {
  param([string]$ChannelRoot)

  if ([string]::IsNullOrWhiteSpace($ChannelRoot) -or -not (Test-Path -LiteralPath $ChannelRoot)) {
    return @()
  }

  $items = @(Get-ChildItem -LiteralPath $ChannelRoot -Directory -Filter 'app-*' -ErrorAction SilentlyContinue |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'Discord.exe') })

  return @($items | Sort-Object @{
      Expression = {
        try { [version](($_.Name -replace '^app-', '')) } catch { [version]'0.0.0.0' }
      }
      Descending = $true
    }, @{
      Expression = { $_.LastWriteTime }
      Descending = $true
    })
}

function Get-DiscordChannelState {
  param(
    [Parameter(Mandatory = $true)][string]$Channel,
    [Parameter(Mandatory = $true)][string]$ChannelRoot
  )

  $updateExe = Join-Path $ChannelRoot 'Update.exe'
  $appDirs = @(Get-DiscordAppDirectories -ChannelRoot $ChannelRoot)
  $latestApp = $appDirs | Select-Object -First 1
  $runningProcesses = @(Get-DiscordProcesses | Where-Object {
    $_.Path -and $_.Path.StartsWith($ChannelRoot, [System.StringComparison]::OrdinalIgnoreCase)
  })
  $runningApp = $null
  if ($runningProcesses.Count -gt 0) {
    $runningPath = Split-Path -Parent $runningProcesses[0].Path
    if (Test-Path -LiteralPath $runningPath) {
      $runningApp = Get-Item -LiteralPath $runningPath
    }
  }

  $downloadPath = Join-Path $ChannelRoot 'download'
  $packagesPath = Join-Path $ChannelRoot 'packages'
  $installerDb = Join-Path $ChannelRoot 'installer.db'
  $downloadWriteTime = if (Test-Path -LiteralPath $downloadPath) { (Get-Item -LiteralPath $downloadPath).LastWriteTime.ToString('o') } else { $null }
  $packagesWriteTime = if (Test-Path -LiteralPath $packagesPath) { (Get-Item -LiteralPath $packagesPath).LastWriteTime.ToString('o') } else { $null }
  $installerDbWriteTime = if (Test-Path -LiteralPath $installerDb) { (Get-Item -LiteralPath $installerDb).LastWriteTime.ToString('o') } else { $null }
  $updaterProcesses = @(Get-DiscordUpdaterProcesses)

  $pendingUpdate = $false
  $pendingReason = $null
  if ($runningApp -and $latestApp -and $runningApp.FullName -ne $latestApp.FullName) {
    $pendingUpdate = $true
    $pendingReason = 'newer app folder is staged while Discord is still running an older folder'
  } elseif ($updaterProcesses.Count -gt 0) {
    $pendingUpdate = $true
    $pendingReason = 'Discord updater process is active'
  } elseif (-not $runningApp -and $latestApp -and $downloadWriteTime) {
    $pendingReason = 'Discord is not running; pending state is unknown'
  }

  $installState = if (-not (Test-Path -LiteralPath $ChannelRoot)) {
    'missing'
  } elseif ($pendingUpdate) {
    'update-ready'
  } elseif ($runningProcesses.Count -gt 0) {
    'running'
  } elseif ($latestApp) {
    'installed'
  } else {
    'unknown'
  }

  return [pscustomobject]@{
    channel = $Channel
    root = $ChannelRoot
    update_exe_present = [bool](Test-Path -LiteralPath $updateExe)
    install_present = [bool](Test-Path -LiteralPath $ChannelRoot)
    install_state = $installState
    app_count = $appDirs.Count
    app_paths = @($appDirs | ForEach-Object FullName)
    latest_app_path = if ($latestApp) { $latestApp.FullName } else { $null }
    latest_app_version = if ($latestApp) { ($latestApp.Name -replace '^app-', '') } else { $null }
    latest_app_write_time = if ($latestApp) { $latestApp.LastWriteTime.ToString('o') } else { $null }
    running_process_count = $runningProcesses.Count
    running_app_path = if ($runningApp) { $runningApp.FullName } else { $null }
    running_app_version = if ($runningApp) { ($runningApp.Name -replace '^app-', '') } else { $null }
    updater_process_count = $updaterProcesses.Count
    pending_update = $pendingUpdate
    pending_update_reason = $pendingReason
    download_write_time = $downloadWriteTime
    packages_write_time = $packagesWriteTime
    installer_db_write_time = $installerDbWriteTime
  }
}

function Get-DiscordWorkflowState {
  param([hashtable]$ExistingState)

  $channelStates = @()
  foreach ($root in @($TargetProfile.DiscordRoots)) {
    $channelStates += Get-DiscordChannelState -Channel $root.Channel -ChannelRoot $root.Root
  }

  $stableChannel = $channelStates | Where-Object channel -eq 'stable' | Select-Object -First 1
  $currentSignature = Get-DiscordAppSignature
  $currentAppPath = if ($currentSignature) { $currentSignature.Path } else { $null }
  $currentInjection = if ($currentAppPath) { Test-BetterDiscordInjection -DiscordAppPath $currentAppPath } else { $false }
  $runtimePresent = Test-Path -LiteralPath (Join-Path $ActiveData 'betterdiscord.asar')
  $reasons = New-Object System.Collections.Generic.List[string]

  if (-not $currentInjection) { $reasons.Add('BetterDiscord injection missing on current Discord app') }
  if (-not $runtimePresent) { $reasons.Add('BetterDiscord runtime missing') }
  if ($ExistingState.last_successful_repair_discord_app_path -and $currentSignature -and $ExistingState.last_successful_repair_discord_app_path -ne $currentSignature.Path) {
    $reasons.Add('Discord app path changed since the last successful repair')
  }
  if ($ExistingState.last_successful_repair_discord_app_write_time -and $currentSignature -and $ExistingState.last_successful_repair_discord_app_write_time -ne $currentSignature.WriteTime) {
    $reasons.Add('Discord app write time changed since the last successful repair')
  }

  return [pscustomobject]@{
    checked_at = (Get-Date).ToString('o')
    target_user = $TargetProfile.UserName
    betterdiscord_root = $ActiveBDRoot
    stable_discord_root = $DiscordRoot
    channel_states = $channelStates
    supported_channel = 'stable'
    stable_channel = $stableChannel
    current_discord_app = $currentSignature
    discord_process_running = [bool](Get-DiscordProcesses)
    betterdiscord_runtime_present = $runtimePresent
    betterdiscord_injection_current = $currentInjection
    last_successful_repair_time = $ExistingState.last_repair_time
    last_successful_repair_discord_app_path = $ExistingState.last_successful_repair_discord_app_path
    last_successful_repair_discord_app_write_time = $ExistingState.last_successful_repair_discord_app_write_time
    repair_reasons = @($reasons)
    repair_needed = ($reasons.Count -gt 0)
  }
}

function Write-DiscordWorkflowState {
  param(
    [Parameter(Mandatory = $true)]$WorkflowState,
    [switch]$AsJson
  )

  if ($AsJson) {
    $WorkflowState | ConvertTo-Json -Depth 8 | Write-Host
    return
  }

  Write-Host "Discord update state checked: $($WorkflowState.checked_at)"
  Write-Host "Target user: $($WorkflowState.target_user)"
  Write-Host "Supported repair channel: $($WorkflowState.supported_channel)"
  foreach ($channelState in @($WorkflowState.channel_states)) {
    Write-Host ("Channel {0}: state={1}; root={2}; running={3}; latest={4}; pending_update={5}" -f
      $channelState.channel,
      $channelState.install_state,
      $channelState.root,
      $(if ($channelState.running_app_version) { $channelState.running_app_version } else { 'none' }),
      $(if ($channelState.latest_app_version) { $channelState.latest_app_version } else { 'none' }),
      $channelState.pending_update)
    if ($channelState.pending_update_reason) {
      Write-Host "  Pending reason: $($channelState.pending_update_reason)"
    }
  }
  Write-Host "BetterDiscord runtime present: $($WorkflowState.betterdiscord_runtime_present)"
  Write-Host "BetterDiscord injection on current app: $($WorkflowState.betterdiscord_injection_current)"
  Write-Host "Repair needed: $($WorkflowState.repair_needed)"
  if ($WorkflowState.repair_reasons.Count -gt 0) {
    Write-Host "Repair reasons: $($WorkflowState.repair_reasons -join '; ')"
  }
}

function Wait-DiscordUpdateTransition {
  param(
    [Parameter(Mandatory = $true)]$InitialState,
    [int]$TimeoutMinutes = 10,
    [int]$PollSeconds = 2,
    [int]$QuietSeconds = 15
  )

  $timeoutMinutes = [math]::Max($TimeoutMinutes, 1)
  $quietSeconds = [math]::Max($QuietSeconds, 1)
  $deadline = (Get-Date).AddMinutes($timeoutMinutes)
  $initialPath = $InitialState.current_discord_app.Path
  $initialWriteTime = $InitialState.current_discord_app.WriteTime
  $quietUntil = $null

  Write-Log ("Monitoring Discord update state for up to {0} minute(s)." -f $timeoutMinutes)
  while ((Get-Date) -lt $deadline) {
    $current = Get-DiscordWorkflowState -ExistingState $state
    $currentPath = $current.current_discord_app.Path
    $currentWriteTime = $current.current_discord_app.WriteTime
    $changed = (
      ($initialPath -and $currentPath -and $initialPath -ne $currentPath) -or
      ($initialWriteTime -and $currentWriteTime -and $initialWriteTime -ne $currentWriteTime)
    )
    $updaterActive = ($current.stable_channel.updater_process_count -gt 0)

    if ($changed -and -not $updaterActive) {
      if (-not $quietUntil) {
        $quietUntil = (Get-Date).AddSeconds($quietSeconds)
        Write-Log "Discord update transition detected. Waiting $quietSeconds quiet second(s) for stability."
      } elseif ((Get-Date) -ge $quietUntil) {
        $stable = Wait-DiscordAppStable -StabilizeSeconds $DiscordStabilizeSeconds -PollSeconds $DiscordStabilizePollSeconds
        $final = Get-DiscordWorkflowState -ExistingState $state
        Write-Log ("Discord update monitor observed stable app path: {0}" -f $(if ($stable) { $stable.Path } else { 'unknown' }))
        return $final
      }
    } else {
      $quietUntil = $null
    }

    Start-Sleep -Seconds ([math]::Max($PollSeconds, 1))
  }

  Write-Log 'Discord update monitor timed out before a stable transition was observed.' 'WARN'
  return $null
}

function Wait-DiscordProcess {
  param([int]$TimeoutSeconds = 300, [int]$PollSeconds = 2)

  $deadline = (Get-Date).AddSeconds([math]::Max($TimeoutSeconds, 1))
  while ((Get-Date) -lt $deadline) {
    $processes = Get-DiscordProcesses
    if ($processes.Count -gt 0) {
      Write-Log ("Discord process detected: {0}" -f (($processes.Id) -join ', '))
      return $true
    }
    Start-Sleep -Seconds ([math]::Max($PollSeconds, 1))
  }
  Write-Log "Discord did not start during the $TimeoutSeconds-second watch window."
  return $false
}

function Wait-DiscordAppStable {
  param([int]$StabilizeSeconds = 10, [int]$PollSeconds = 2)

  if ($StabilizeSeconds -le 0) { return Get-DiscordAppSignature }
  $deadline = (Get-Date).AddSeconds($StabilizeSeconds)
  $previous = $null
  while ((Get-Date) -lt $deadline) {
    $current = Get-DiscordAppSignature
    if ($previous -and $current -and $previous.Path -eq $current.Path -and $previous.WriteTime -eq $current.WriteTime) {
      Write-Log "Discord app stabilized: $($current.Path)"
      return $current
    }
    $previous = $current
    Start-Sleep -Seconds ([math]::Max($PollSeconds, 1))
  }
  Write-Log 'Discord stabilization window elapsed; using the latest app signature.' 'WARN'
  return Get-DiscordAppSignature
}

function Test-BetterDiscordInjection {
  param([string]$DiscordAppPath)

  if ([string]::IsNullOrWhiteSpace($DiscordAppPath)) { return $false }
  $coreIndex = Join-Path $DiscordAppPath 'modules\discord_desktop_core-1\discord_desktop_core\index.js'
  if (-not (Test-Path -LiteralPath $coreIndex)) { return $false }
  try {
    $text = Get-Content -LiteralPath $coreIndex -Raw
    $hasAsar = $text -match '(?is)BetterDiscord.{0,160}data.{0,160}betterdiscord\.asar'
    $hasInjectionMarker = $text -match "(?i)BetterDiscord'?s Injection Script"
    return [bool]($hasAsar -and $hasInjectionMarker)
  } catch {
    Write-Log "Could not inspect Discord core index. $_" 'WARN'
    return $false
  }
}

function Get-BdcliPath {
  $localCli = Join-Path $RootDir 'bin\bdcli.exe'
  if (Test-Path -LiteralPath $localCli) { return $localCli }

  $command = Get-Command bdcli -ErrorAction SilentlyContinue
  if ($command -and $command.Source -and (Test-Path -LiteralPath $command.Source)) { return $command.Source }

  $wingetLink = Join-Path $TargetProfile.LocalAppData 'Microsoft\WinGet\Links\bdcli.exe'
  if (Test-Path -LiteralPath $wingetLink) { return $wingetLink }
  return $null
}

function Get-BdcliForRepair {
  $existingCli = Get-BdcliPath
  if ($existingCli -and (Test-Path -LiteralPath $existingCli)) {
    Write-Log "Using existing BetterDiscord CLI: $existingCli"
    return $existingCli
  }

  $binDir = Join-Path $RootDir 'bin'
  $targetCli = Join-Path $binDir 'bdcli.exe'
  $tempRoot = Join-Path $env:TEMP ("bd-auto-cli-{0}" -f [guid]::NewGuid().ToString('N'))
  $zipPath = "$tempRoot.zip"
  $checksumPath = "$tempRoot-checksums.txt"

  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'BD-AUTO Watchdog' }
    Write-Log 'No local BetterDiscord CLI was found; downloading the official checksum-verified CLI.'
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/BetterDiscord/cli/releases/latest' -Headers $headers
    $asset = $release.assets |
      Where-Object { $_.name -match '(?i)bdcli_.*_windows_amd64\.zip$' -or $_.name -match '(?i)windows.*amd64.*\.zip$' } |
      Select-Object -First 1
    $checksumAsset = $release.assets | Where-Object name -eq 'bdcli_checksums.txt' | Select-Object -First 1
    if (-not $asset -or -not $checksumAsset) {
      throw 'The BetterDiscord CLI release is missing its Windows archive or checksum file.'
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

    New-Item -ItemType Directory -Force -Path $tempRoot, $binDir | Out-Null
    Expand-Archive -LiteralPath $zipPath -DestinationPath $tempRoot -Force
    $downloadedCli = Get-ChildItem -LiteralPath $tempRoot -Recurse -Filter 'bdcli.exe' -File |
      Select-Object -First 1
    if (-not $downloadedCli) { throw 'bdcli.exe was not found in the verified archive.' }

    $stagedCli = "$targetCli.tmp-$([guid]::NewGuid().ToString('N'))"
    Copy-Item -LiteralPath $downloadedCli.FullName -Destination $stagedCli -Force
    Move-Item -LiteralPath $stagedCli -Destination $targetCli -Force
    Write-Log "BetterDiscord CLI $($release.tag_name) is ready."
    return $targetCli
  } catch {
    throw "BetterDiscord CLI download failed and no existing binary is available. $_"
  } finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $checksumPath -Force -ErrorAction SilentlyContinue
    if ($stagedCli) { Remove-Item -LiteralPath $stagedCli -Force -ErrorAction SilentlyContinue }
  }
}

function Stop-Discord {
  param([int]$GracefulTimeoutSeconds = 3, [int]$ForceAttempts = 5)

  $processes = @(Get-DiscordProcesses | Sort-Object Id -Unique)
  if ($processes.Count -eq 0) { return @() }

  foreach ($process in $processes) {
    try { [void]$process.CloseMainWindow() } catch { }
  }

  $deadline = (Get-Date).AddSeconds($GracefulTimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $remaining = @(Get-DiscordProcesses)
    if ($remaining.Count -eq 0) { return $processes }
    Start-Sleep -Milliseconds 500
  }

  for ($attempt = 1; $attempt -le $ForceAttempts; $attempt++) {
    $remaining = @(Get-DiscordProcesses | Sort-Object Id -Unique)
    if ($remaining.Count -eq 0) { return $processes }

    foreach ($process in $remaining) {
      try {
        Stop-Process -Id $process.Id -Force -ErrorAction Stop
      } catch {
        try { & taskkill.exe /PID $process.Id /T /F 2>&1 | Out-Null } catch { }
      }
    }
    Start-Sleep -Seconds 1
  }

  $remaining = @(Get-DiscordProcesses)
  if ($remaining.Count -gt 0) {
    throw "Could not stop all target Discord processes: $($remaining.Id -join ', ')"
  }
  return $processes
}

function Start-Discord {
  if (Get-DiscordProcesses) {
    Write-Log 'Discord is already running.'
    return $true
  }

  $updateExe = Join-Path $DiscordRoot 'Update.exe'
  if (-not (Test-Path -LiteralPath $updateExe)) {
    Write-Log "Discord launcher not found: $updateExe" 'ERROR'
    return $false
  }

  if (Test-BDAutoAdministrator) {
    try {
      $shell = New-Object -ComObject Shell.Application
      $shell.ShellExecute($updateExe, '--processStart Discord.exe', $DiscordRoot, 'open', 1)
      Write-Log 'Discord relaunch delegated to the interactive Explorer shell to avoid an elevated Discord process.'
    } catch {
      Write-Log "Explorer-shell launch failed; using direct launch. $_" 'WARN'
      Start-Process -FilePath $updateExe -ArgumentList '--processStart Discord.exe' | Out-Null
    }
  } else {
    Start-Process -FilePath $updateExe -ArgumentList '--processStart Discord.exe' | Out-Null
  }
  $deadline = (Get-Date).AddSeconds(30)
  while ((Get-Date) -lt $deadline) {
    if (Get-DiscordProcesses) {
      Write-Log 'Discord relaunched successfully.'
      return $true
    }
    Start-Sleep -Seconds 2
  }
  Write-Log 'Discord relaunch timed out after 30 seconds.' 'ERROR'
  return $false
}

function Invoke-AddonSync {
  param([switch]$Verify, [switch]$Audit)

  if (-not (Test-Path -LiteralPath $AddonSyncPath)) { throw "Addon sync script missing: $AddonSyncPath" }
  $arguments = @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', $AddonSyncPath,
    '-ManifestPath', $ManifestPath,
    '-ActiveRoot', $ActiveBDRoot,
    '-CacheRoot', $AddonCacheRoot,
    '-BackupRoot', (Join-Path $BackupRoot 'addon-sync'),
    '-ReportPath', $AddonReportPath,
    '-RemoveRecognizedDuplicates'
  )
  if ($Verify) { $arguments += '-VerifyOnly' }
  if ($Audit) { $arguments += '-AuditOnly' }
  & powershell.exe @arguments | ForEach-Object { Write-Log "$_" }
  if ($LASTEXITCODE -ne 0) {
    throw "Addon sync exited with code $LASTEXITCODE"
  }
  if (Test-Path -LiteralPath $AddonReportPath) {
    return Get-Content -LiteralPath $AddonReportPath -Raw | ConvertFrom-Json
  }
  return $null
}

function New-RepairBackup {
  $backupPath = Join-Path $BackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
  New-Item -ItemType Directory -Force -Path $backupPath | Out-Null
  if (Test-Path -LiteralPath $ActivePlugins) {
    Copy-Item -LiteralPath $ActivePlugins -Destination (Join-Path $backupPath 'plugins') -Recurse -Force
  }
  if (Test-Path -LiteralPath $ActiveThemes) {
    Copy-Item -LiteralPath $ActiveThemes -Destination (Join-Path $backupPath 'themes') -Recurse -Force
  }
  if (Test-Path -LiteralPath $ActiveData) {
    Copy-Item -LiteralPath $ActiveData -Destination (Join-Path $backupPath 'data') -Recurse -Force
  }
  @{
    created = (Get-Date).ToString('o')
    discord_app = (Get-DiscordAppSignature)
    plugin_count = (Get-Count -Path $ActivePlugins -Filter '*.plugin.js')
    theme_count = (Get-Count -Path $ActiveThemes -Filter '*.theme.css')
  } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backupPath 'backup-manifest.json') -Encoding UTF8
  return $backupPath
}

function Remove-OldBackups {
  param([int]$Keep = 3)
  if ($Keep -lt 1) { $Keep = 1 }
  $old = Get-ChildItem -LiteralPath $BackupRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -Skip $Keep
  foreach ($directory in $old) {
    $resolved = $directory.FullName
    if ($resolved.StartsWith($BackupRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      Remove-Item -LiteralPath $resolved -Recurse -Force
      Write-Log "Removed expired backup: $resolved"
    }
  }
}

function Repair-WatchdogTaskDefinition {
  $taskName = 'BetterDiscord Auto Repair Watchdog'
  $taskInstaller = Join-Path $BaseDir 'Install-BetterDiscord-WatchdogTask.ps1'
  $scheduleService = Get-Service -Name 'Schedule' -ErrorAction SilentlyContinue
  if (
    -not $scheduleService -or
    $scheduleService.StartType -eq 'Disabled' -or
    -not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)
  ) {
    Write-Log 'Scheduled task infrastructure is unavailable; manual repair remains available.' 'WARN'
    return
  }

  try {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  } catch {
    Write-Log "Scheduled task inspection failed; manual repair remains available. $_" 'WARN'
    return
  }
  if (-not $task) { return }

  $arguments = [string]$task.Actions[0].Arguments
  $triggerClasses = @($task.Triggers | ForEach-Object { $_.CimClass.CimClassName })
  $hasLogonTrigger = $triggerClasses -contains 'MSFT_TaskLogonTrigger'
  $hasEventTrigger = $triggerClasses -contains 'MSFT_TaskEventTrigger'
  $hasTimeTrigger = $triggerClasses -contains 'MSFT_TaskTimeTrigger'
  $definitionCurrent = (
    $arguments -match '-WaitForDiscord' -and
    $arguments -match '-RepairAfterDiscordUpdate' -and
    $arguments -match '-ReopenDiscord' -and
    $arguments -match '-NoElevationPrompt' -and
    $arguments -match '-DiscordWaitTimeoutSeconds 300' -and
    $arguments -match '-TargetRoamingAppData' -and
    $arguments -match [regex]::Escape($TargetProfile.RoamingAppData) -and
    $hasLogonTrigger -and
    $hasEventTrigger -and
    -not $hasTimeTrigger
  )
  if ($definitionCurrent) { return }

  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Write-Log 'Scheduled task definition is stale; an elevated run is required to update it.' 'WARN'
    return
  }

  try {
    Write-Log 'Updating stale scheduled task definition.'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $taskInstaller `
      -TargetUserName $TargetProfile.UserName `
      -TargetUserSid $TargetProfile.UserSid `
      -TargetRoamingAppData $TargetProfile.RoamingAppData `
      -TargetLocalAppData $TargetProfile.LocalAppData | ForEach-Object { Write-Log "$_" }
    if ($LASTEXITCODE -ne 0) {
      Write-Log "Scheduled task update failed with exit code $LASTEXITCODE; manual repair remains available." 'WARN'
    }
  } catch {
    Write-Log "Scheduled task update failed; manual repair remains available. $_" 'WARN'
  }
}

function Invoke-ElevatedRepair {
  $powerShell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $arguments = @(
    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', $PSCommandPath,
    '-ElevatedRepair',
    '-TargetUserName', $TargetProfile.UserName,
    '-TargetRoamingAppData', $TargetProfile.RoamingAppData,
    '-TargetLocalAppData', $TargetProfile.LocalAppData,
    '-BackupRetentionCount', $BackupRetentionCount
  )
  if ($ForceRepair) { $arguments += '-ForceRepair' }
  if ($ReopenDiscord) { $arguments += '-ReopenDiscord' }
  if ($NoReopenDiscord) { $arguments += '-NoReopenDiscord' }
  if ($RestoreStash) { $arguments += '-RestoreStash' }
  $argumentLine = ($arguments | ForEach-Object {
    $value = [string]$_
    if ($value -match '[\s"]') {
      '"' + ($value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
    } else {
      $value
    }
  }) -join ' '

  Write-Log 'Repair requires elevation. Requesting Windows UAC approval.'
  try {
    $process = Start-Process -FilePath $powerShell -Verb RunAs -ArgumentList $argumentLine -PassThru
  } catch {
    throw "Repair elevation was cancelled or unavailable. $_"
  }
  if (-not $process.WaitForExit(600000)) {
    throw 'Elevated repair did not finish within 10 minutes.'
  }
  if ($process.ExitCode -ne 0) {
    throw "Elevated repair failed with exit code $($process.ExitCode)."
  }
  exit 0
}

$state = Load-State
Write-Log "BD-AUTO version: $(Get-BDAutoVersion)"
Write-BDAutoTargetProfileLog -Profile $TargetProfile -WriteLog ${function:Write-Log}
$compatibility = Get-BDAutoCompatibilityReport -TargetProfile $TargetProfile -RootPath $RootDir
Write-BDAutoCompatibilityLog -Report $compatibility -WriteLog ${function:Write-Log}
Save-BDAutoCompatibilityReport -Report $compatibility -Path (Join-Path $RuntimeRoot 'compatibility.json')
if ($Status) {
  Show-Status
  exit 0
}
if ($AddonAudit) {
  $audit = Invoke-AddonSync -Audit
  Write-Host "Addon audit report: $AddonReportPath"
  Write-Host "Addons: $($audit.addon_count); problems: $($audit.problem_count)"
  exit 0
}
if ($CheckDiscordUpdateState) {
  $workflowState = Get-DiscordWorkflowState -ExistingState $state
  $state.last_check_time = $workflowState.checked_at
  $state.last_check_result = if ($workflowState.repair_needed) { 'repair-needed' } else { 'healthy' }
  $state.last_discord_workflow_state = $workflowState
  Save-State $state
  Write-DiscordWorkflowState -WorkflowState $workflowState
  exit 0
}
Repair-WatchdogTaskDefinition
if ($StartupDelaySeconds -gt 0) {
  Write-Log "Startup delay: $StartupDelaySeconds second(s)."
  Start-Sleep -Seconds $StartupDelaySeconds
}

if ($RepairAfterDiscordUpdate) {
  $initialWorkflowState = Get-DiscordWorkflowState -ExistingState $state
  Write-Log 'RepairAfterDiscordUpdate command requested.'
  Write-DiscordWorkflowState -WorkflowState $initialWorkflowState

  if (-not $initialWorkflowState.stable_channel.install_present) {
    throw 'Discord Stable is not installed for the target profile.'
  }

  if ($initialWorkflowState.stable_channel.pending_update) {
    Write-Log 'Pending Discord update detected; applying it through the local Discord Update.exe flow.'
    if (Get-DiscordProcesses) {
      $stopped = Stop-Discord
      Write-Log ("Stopped Discord process IDs for update application: {0}" -f (($stopped.Id) -join ', '))
    }
    if (-not (Start-Discord)) {
      throw 'Discord update application could not start the local Discord launcher.'
    }
  } else {
    Write-Log 'No pending Discord update was detected; continuing with post-update health verification only.'
  }

  $monitoredState = Wait-DiscordUpdateTransition -InitialState $initialWorkflowState -TimeoutMinutes $MonitorTimeoutMinutes -PollSeconds $DiscordStabilizePollSeconds -QuietSeconds $UpdateQuietSeconds
  if (-not $monitoredState) {
    $state.last_check_time = (Get-Date).ToString('o')
    $state.last_check_result = 'discord-update-monitor-timeout'
    Save-State $state
    throw "Discord update did not reach a stable state within $MonitorTimeoutMinutes minute(s)."
  }
  Write-DiscordWorkflowState -WorkflowState $monitoredState
}

if ($MonitorDiscordUpdate) {
  $initialWorkflowState = Get-DiscordWorkflowState -ExistingState $state
  Write-Log 'MonitorDiscordUpdate command requested.'
  Write-DiscordWorkflowState -WorkflowState $initialWorkflowState
  $monitoredState = Wait-DiscordUpdateTransition -InitialState $initialWorkflowState -TimeoutMinutes $MonitorTimeoutMinutes -PollSeconds $DiscordStabilizePollSeconds -QuietSeconds $UpdateQuietSeconds
  if (-not $monitoredState) {
    $state.last_check_time = (Get-Date).ToString('o')
    $state.last_check_result = 'discord-update-monitor-timeout'
    Save-State $state
    if ($DryRun) {
      Write-Log 'Dry-run monitor ended without an observed update transition.'
      exit 0
    }
    throw "Discord update did not reach a stable state within $MonitorTimeoutMinutes minute(s)."
  }
  $state.last_discord_workflow_state = $monitoredState
  Save-State $state
  Write-DiscordWorkflowState -WorkflowState $monitoredState
}

if ($WaitForDiscord -and -not (Get-DiscordProcesses)) {
  if (-not (Wait-DiscordProcess -TimeoutSeconds $DiscordWaitTimeoutSeconds)) {
    $state.last_check_time = (Get-Date).ToString('o')
    $state.last_check_result = 'discord-not-started'
    Save-State $state
    exit 0
  }
}

$stableSignature = Wait-DiscordAppStable -StabilizeSeconds $DiscordStabilizeSeconds -PollSeconds $DiscordStabilizePollSeconds
if (-not $stableSignature) {
  Write-Log 'Discord installation was not found.' 'ERROR'
  $state.last_check_time = (Get-Date).ToString('o')
  $state.last_check_result = 'discord-install-missing'
  Save-State $state
  exit 1
}

$injectionInstalled = Test-BetterDiscordInjection -DiscordAppPath $stableSignature.Path
$addonVerificationFailed = $false
$addonReport = $null
try {
  $addonReport = Invoke-AddonSync -Verify:$DryRun
} catch {
  $addonVerificationFailed = $true
  Write-Log "Addon verification/sync failed: $_" 'ERROR'
}

$reasons = New-Object System.Collections.Generic.List[string]
if ($ForceRepair) { $reasons.Add('ForceRepair specified') }
if (-not $injectionInstalled) { $reasons.Add('BetterDiscord injection missing') }
if (-not (Test-Path -LiteralPath (Join-Path $ActiveData 'betterdiscord.asar'))) { $reasons.Add('BetterDiscord runtime missing') }
if (
  $state.last_successful_repair_discord_app_path -and
  $state.last_successful_repair_discord_app_path -ne $stableSignature.Path
) {
  $reasons.Add('Discord app path changed since the last successful repair')
}
if (
  $state.last_successful_repair_discord_app_write_time -and
  $state.last_successful_repair_discord_app_write_time -ne $stableSignature.WriteTime
) {
  $reasons.Add('Discord app write time changed since the last successful repair')
}
if ($addonVerificationFailed) {
  $reasons.Add($(if ($DryRun) { 'Addon verification failed' } else { 'Addon synchronization failed' }))
}

$repairNeeded = $reasons.Count -gt 0
Write-Log "Discord app: $($stableSignature.Path)"
Write-Log "BetterDiscord injection installed: $injectionInstalled"
Write-Log "Active addons: plugins=$(Get-Count -Path $ActivePlugins -Filter '*.plugin.js'), themes=$(Get-Count -Path $ActiveThemes -Filter '*.theme.css')"
Write-Log ("Repair needed: {0}; reasons: {1}" -f $repairNeeded, ($reasons -join '; '))

$state.last_check_time = (Get-Date).ToString('o')
$state.last_discord_app_path = $stableSignature.Path
$state.last_discord_app_write_time = $stableSignature.WriteTime
$state.last_check_result = if ($repairNeeded) { 'repair-needed' } else { 'healthy' }
$state.last_addon_report_path = $AddonReportPath
if ($addonReport) {
  $state.last_addon_changed_count = $addonReport.changed_count
  $state.last_addon_problem_count = $addonReport.problem_count
}

if (-not $repairNeeded) {
  Save-State $state
  Write-Log 'No-op: installation is healthy.'
  exit 0
}

if ($DryRun) {
  Save-State $state
  Write-Log 'Dry run complete; no changes were made.'
  exit 0
}

if ($addonVerificationFailed) {
  Save-State $state
  throw 'Cannot continue while addon synchronization is failing.'
}

$backupPath = New-RepairBackup
Write-Log "Backup created: $backupPath"
$wasRunning = [bool](Get-DiscordProcesses)
if ($wasRunning) {
  $stopped = Stop-Discord
  Write-Log ("Stopped Discord process IDs: {0}" -f (($stopped.Id) -join ', '))
}

$bdcli = Get-BdcliForRepair

$output = & $bdcli install --path $stableSignature.Path 2>&1 | Out-String
Write-Log "bdcli output: $output"
$installExitCode = $LASTEXITCODE
if ($installExitCode -ne 0) {
  if ($wasRunning -and -not $NoReopenDiscord) { [void](Start-Discord) }
  $state.last_repair_result = "bdcli-exit-$installExitCode"
  Save-State $state
  if (-not (Test-BDAutoAdministrator) -and -not $ElevatedRepair) {
    if ($NoElevationPrompt) {
      $state.last_check_result = 'repair-requires-elevation'
      Save-State $state
      Write-Log 'Non-elevated repair failed. Hidden automation will not display UAC; use the Repair BetterDiscord shortcut.' 'WARN'
      exit 2
    }
    Write-Log 'Non-elevated repair failed; retrying once with Windows UAC approval.' 'WARN'
    Invoke-ElevatedRepair
  }
  throw "BetterDiscord repair failed with exit code $installExitCode"
}

$addonReport = Invoke-AddonSync
$shouldReopen = -not $NoReopenDiscord -and ($wasRunning -or $ReopenDiscord)
$reopened = if ($shouldReopen) { Start-Discord } else { $false }
$postInjection = Test-BetterDiscordInjection -DiscordAppPath $stableSignature.Path

$state.last_repair_time = (Get-Date).ToString('o')
$state.last_repair_result = if ($postInjection) { 'completed' } else { 'post-repair-injection-missing' }
$state.last_check_result = if ($postInjection) { 'healthy' } else { 'repair-failed-verification' }
$state.last_backup_path = $backupPath
$state.last_successful_repair_discord_app_path = $stableSignature.Path
$state.last_successful_repair_discord_app_write_time = $stableSignature.WriteTime
$state.discord_was_running_before_repair = $wasRunning
$state.discord_reopen_attempted = $shouldReopen
$state.discord_reopen_success = $reopened
$state.post_repair_injection_installed = $postInjection
$state.repair_method = 'bdcli'
$state.bdcli_path = $bdcli
$state.last_addon_report_path = $AddonReportPath
if ($addonReport) {
  $state.last_addon_changed_count = $addonReport.changed_count
  $state.last_addon_problem_count = $addonReport.problem_count
}
$state.active_plugin_count = Get-Count -Path $ActivePlugins -Filter '*.plugin.js'
$state.active_theme_count = Get-Count -Path $ActiveThemes -Filter '*.theme.css'
$state.target_user = $TargetProfile.UserName
$state.target_user_sid = $TargetProfile.UserSid
$state.target_betterdiscord_root = $TargetProfile.BetterDiscordRoot
$state.target_discord_root = $TargetProfile.DiscordRoot
Save-State $state
Remove-OldBackups -Keep $BackupRetentionCount

if (-not $postInjection) {
  throw 'Repair completed but BetterDiscord injection could not be verified.'
}
if ($shouldReopen -and -not $reopened) {
  throw 'Repair completed but Discord did not relaunch.'
}

Write-Log 'Watchdog repair completed successfully.'
