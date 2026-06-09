[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'payload\Get-BDAutoCompatibility.ps1')

$profile = [pscustomobject]@{
  UserName = 'TEST\User'
  UserSid = 'S-1-5-21-0-0-0-1001'
  RoamingAppData = 'C:\Users\User\AppData\Roaming'
  LocalAppData = 'C:\Users\User\AppData\Local'
  DiscordRoot = 'C:\Users\User\AppData\Local\Discord'
  BetterDiscordRoot = 'C:\Users\User\AppData\Roaming\BetterDiscord'
}

$reduced = Get-BDAutoCompatibilityReport -TargetProfile $profile -RootPath $repoRoot -CapabilityOverrides @{
  CimAvailable = $false
  TaskServicePresent = $false
  TaskServiceStatus = 'Unavailable'
  TaskServiceStartType = 'Unknown'
  TaskCmdletsPresent = $false
  DefenderServicePresent = $false
  SecurityHealthServicePresent = $false
  BrandingText = 'Ghost Spectre Superlite'
}

if (-not $reduced.CustomWindowsSuspected) {
  throw 'Reduced/custom Windows simulation was not detected.'
}
if ($reduced.TaskSchedulerAvailable) {
  throw 'Task Scheduler should be unavailable in the reduced Windows simulation.'
}
if ($reduced.CustomWindowsIndicators.Count -lt 2) {
  throw 'Reduced/custom Windows indicators were not recorded.'
}

Write-Host '[PASS] Reduced/custom Windows compatibility simulation'
