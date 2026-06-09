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

$userSid = $targetProfile.UserSid
$userName = $targetProfile.UserName
$escapedScriptPath = [Security.SecurityElement]::Escape($scriptPath)
$escapedUserSid = [Security.SecurityElement]::Escape($userSid)
$escapedAuthor = [Security.SecurityElement]::Escape($userName)
$watchdogArguments = (
  '-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass ' +
  "-File `"$scriptPath`" -WaitForDiscord " +
  '-DiscordWaitTimeoutSeconds 300 -DiscordStabilizeSeconds 10 -DiscordStabilizePollSeconds 2 ' +
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

Register-ScheduledTask -TaskName $taskName -Xml $taskXml -Force | Out-Null
Write-Host "Installed scheduled task: $taskName"
Write-Host "Target user: $($targetProfile.UserName) [$($targetProfile.UserSid)]"
Write-Host "Target BetterDiscord: $($targetProfile.BetterDiscordRoot)"
Write-Host "Target Discord: $($targetProfile.DiscordRoot)"
Write-Host 'Triggers: user logon and resume from sleep. No recurring timer.'
