[CmdletBinding()]
param(
  [string]$TargetUserName,
  [string]$TargetUserSid,
  [string]$TargetRoamingAppData,
  [string]$TargetLocalAppData,
  [string]$ProfileStatePath = 'C:\Tools\BD-AUTO\runtime\target-profile.json'
)

$ErrorActionPreference = 'Stop'

$taskName = 'BetterDiscord Auto Repair Watchdog'
$scriptPath = 'C:\Tools\BD-AUTO\BetterDiscordWatchdog\BetterDiscord-Watchdog.ps1'
$taskStatusPath = Join-Path (Split-Path -Parent $ProfileStatePath) 'task-status.json'
$statusTextPath = 'C:\Tools\BD-AUTO\BD-AUTO-STATUS.txt'
$installedVersionPath = 'C:\Tools\BD-AUTO\runtime\installed-version.json'
$versionFilePath = 'C:\Tools\BD-AUTO\VERSION'

function Write-TaskStatus {
  param(
    [string]$Status,
    [string]$Message,
    [bool]$WakeTriggerInstalled = $false
  )

  $directory = Split-Path -Parent $taskStatusPath
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
  $value = [ordered]@{
    status = $Status
    message = $Message
    task_name = $taskName
    target_user = $TargetUserName
    target_user_sid = $TargetUserSid
    wake_trigger_installed = $WakeTriggerInstalled
    manual_repair_available = Test-Path -LiteralPath $scriptPath
    updated_at = (Get-Date).ToString('o')
  }
  [System.IO.File]::WriteAllText(
    $taskStatusPath,
    ($value | ConvertTo-Json -Depth 4),
    (New-Object System.Text.UTF8Encoding($false))
  )
}

function Update-InstallSummaryTaskStatus {
  param(
    [string]$Status,
    [string]$Message
  )

  $runtimeRoot = Split-Path -Parent $ProfileStatePath
  $resultPath = Join-Path $runtimeRoot 'install-result.json'
  if (Test-Path -LiteralPath $resultPath) {
    try {
      $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
      $result.ScheduledTask = $Status
      [System.IO.File]::WriteAllText(
        $resultPath,
        ($result | ConvertTo-Json -Depth 4),
        (New-Object System.Text.UTF8Encoding($false))
      )
    } catch { }
  }

  $summaryPath = Join-Path $runtimeRoot 'install-summary.txt'
  if (Test-Path -LiteralPath $summaryPath) {
    try {
      $summary = Get-Content -LiteralPath $summaryPath -Raw
      $summary = $summary -replace '(?m)^Scheduled task:.*$', "Scheduled task: $Message"
      [System.IO.File]::WriteAllText(
        $summaryPath,
        $summary,
        (New-Object System.Text.UTF8Encoding($false))
      )
    } catch { }
  }
}

function Update-VersionAndStatusArtifacts {
  param(
    [string]$Status,
    [string]$Message
  )

  if (Test-Path -LiteralPath $installedVersionPath) {
    try {
      $installedVersion = Get-Content -LiteralPath $installedVersionPath -Raw | ConvertFrom-Json
      $installedVersion.scheduled_task_installed = ($Status -in @('installed', 'installed-logon-only'))
      $installedVersion.scheduled_task_status = $Status
      $installedVersion.scheduled_task_message = $Message
      [System.IO.File]::WriteAllText(
        $installedVersionPath,
        ($installedVersion | ConvertTo-Json -Depth 6),
        (New-Object System.Text.UTF8Encoding($false))
      )
    } catch { }
  }

  if (Test-Path -LiteralPath $statusTextPath) {
    try {
      $statusText = Get-Content -LiteralPath $statusTextPath -Raw
      $statusText = $statusText -replace '(?m)^Scheduled task:.*$', "Scheduled task: $Message"
      [System.IO.File]::WriteAllText(
        $statusTextPath,
        $statusText,
        (New-Object System.Text.UTF8Encoding($false))
      )
    } catch { }
  }
}

trap {
  $message = "Scheduled task setup failed: $($_.Exception.Message)"
  try { Write-TaskStatus -Status 'unavailable' -Message $message } catch { }
  try { Update-InstallSummaryTaskStatus -Status 'unavailable' -Message 'unavailable; use the Repair BetterDiscord shortcut after Discord updates' } catch { }
  try { Update-VersionAndStatusArtifacts -Status 'unavailable' -Message 'unavailable; use the Repair BetterDiscord shortcut after Discord updates' } catch { }
  [Console]::Error.WriteLine($message)
  exit 2
}

if (-not (Test-Path -LiteralPath $scriptPath)) {
  throw "Watchdog script not found: $scriptPath"
}

$profileResolverPath = 'C:\Tools\BD-AUTO\Resolve-BDAutoTargetProfile.ps1'
if (-not (Test-Path -LiteralPath $profileResolverPath)) {
  throw "Target profile resolver not found: $profileResolverPath"
}
. $profileResolverPath

if (
  (Test-Path -LiteralPath $ProfileStatePath) -and
  -not $TargetUserName -and
  -not $TargetUserSid -and
  -not $TargetRoamingAppData -and
  -not $TargetLocalAppData
) {
  $savedProfile = Get-Content -LiteralPath $ProfileStatePath -Raw | ConvertFrom-Json
  $TargetUserName = $savedProfile.user_name
  $TargetUserSid = $savedProfile.user_sid
  $TargetRoamingAppData = $savedProfile.roaming_app_data
  $TargetLocalAppData = $savedProfile.local_app_data
}

$targetProfile = Resolve-BDAutoTargetProfile `
  -TargetUserName $TargetUserName `
  -TargetRoamingAppData $TargetRoamingAppData `
  -TargetLocalAppData $TargetLocalAppData
if ($TargetUserSid) { $targetProfile.UserSid = $TargetUserSid }
if (-not $targetProfile.UserSid) {
  throw "Could not resolve a SID for target user '$($targetProfile.UserName)'."
}
$TargetUserName = $targetProfile.UserName
$TargetUserSid = $targetProfile.UserSid

$scheduleService = Get-Service -Name 'Schedule' -ErrorAction SilentlyContinue
if (-not $scheduleService) {
  throw 'Task Scheduler service is unavailable on this Windows installation.'
}
if ($scheduleService.StartType -eq 'Disabled') {
  throw 'Task Scheduler service is disabled on this Windows installation.'
}
if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
  throw 'The ScheduledTasks PowerShell module is unavailable.'
}

$userSid = $targetProfile.UserSid
$userName = $targetProfile.UserName
$escapedScriptPath = [Security.SecurityElement]::Escape($scriptPath)
$escapedUserSid = [Security.SecurityElement]::Escape($userSid)
$escapedAuthor = [Security.SecurityElement]::Escape($userName)
$watchdogArguments = (
  '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass ' +
  "-File `"$scriptPath`" -WaitForDiscord " +
  '-NoElevationPrompt -DiscordWaitTimeoutSeconds 300 -DiscordStabilizeSeconds 10 -DiscordStabilizePollSeconds 2 ' +
  "-TargetUserName `"$($targetProfile.UserName)`" " +
  "-TargetRoamingAppData `"$($targetProfile.RoamingAppData)`" " +
  "-TargetLocalAppData `"$($targetProfile.LocalAppData)`""
)
$escapedWatchdogArguments = [Security.SecurityElement]::Escape($watchdogArguments)
$subscription = @"
<QueryList>
  <Query Id="0" Path="System">
    <Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]</Select>
  </Query>
</QueryList>
"@
$escapedSubscription = [Security.SecurityElement]::Escape($subscription)

$taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>$escapedAuthor</Author>
    <Description>Checks BetterDiscord once after sign-in and once after resume from sleep.</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <Delay>PT5S</Delay>
      <UserId>$escapedUserSid</UserId>
    </LogonTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>$escapedSubscription</Subscription>
      <Delay>PT10S</Delay>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$escapedUserSid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>$escapedWatchdogArguments</Arguments>
      <WorkingDirectory>C:\Tools\BD-AUTO</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

$wakeTriggerInstalled = $true
try {
  Register-ScheduledTask -TaskName $taskName -Xml $taskXml -Force | Out-Null
} catch {
  Write-Warning "Wake-event task registration failed; retrying with the sign-in trigger only. $_"
  $logonOnlyXml = $taskXml -replace '(?s)\s*<EventTrigger>.*?</EventTrigger>', ''
  Register-ScheduledTask -TaskName $taskName -Xml $logonOnlyXml -Force | Out-Null
  $wakeTriggerInstalled = $false
}
$installedTask = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
if (-not $installedTask) { throw 'Task registration returned without an installed task.' }
Write-TaskStatus -Status $(if ($wakeTriggerInstalled) { 'installed' } else { 'installed-logon-only' }) `
  -Message $(if ($wakeTriggerInstalled) {
    'Scheduled repair installed for sign-in and resume from sleep.'
  } else {
    'Scheduled repair installed for sign-in only; the wake event trigger is unavailable.'
  }) `
  -WakeTriggerInstalled $wakeTriggerInstalled
Update-InstallSummaryTaskStatus `
  -Status $(if ($wakeTriggerInstalled) { 'installed' } else { 'installed-logon-only' }) `
  -Message $(if ($wakeTriggerInstalled) {
    'installed for sign-in and resume from sleep'
  } else {
    'installed for sign-in only; wake-event support is unavailable'
  })
Update-VersionAndStatusArtifacts `
  -Status $(if ($wakeTriggerInstalled) { 'installed' } else { 'installed-logon-only' }) `
  -Message $(if ($wakeTriggerInstalled) {
    'installed for sign-in and resume from sleep'
  } else {
    'installed for sign-in only; wake-event support is unavailable'
  })
Write-Host "Installed scheduled task: $taskName"
Write-Host "Target user: $($targetProfile.UserName) [$($targetProfile.UserSid)]"
Write-Host "Target BetterDiscord: $($targetProfile.BetterDiscordRoot)"
Write-Host "Target Discord: $($targetProfile.DiscordRoot)"
Write-Host $(if ($wakeTriggerInstalled) {
  'Triggers: user logon and resume from sleep. No recurring timer.'
} else {
  'Triggers: user logon only. Wake-event support is unavailable; no recurring timer.'
})
