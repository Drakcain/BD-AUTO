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
  EnableLUA = 1
  ConsentPromptBehaviorAdmin = 0
  PromptOnSecureDesktop = 1
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
if ($reduced.UacElevationMode -ne 'auto-elevate-administrators') {
  throw 'Ghost Spectre-style automatic elevation policy was not detected.'
}

$stock = Get-BDAutoCompatibilityReport -TargetProfile $profile -RootPath $repoRoot -CapabilityOverrides @{
  CimAvailable = $true
  TaskServicePresent = $true
  TaskServiceStatus = 'Running'
  TaskServiceStartType = 'Automatic'
  TaskCmdletsPresent = $true
  DefenderServicePresent = $true
  SecurityHealthServicePresent = $true
  BrandingText = 'Microsoft Windows 11 Pro'
  EnableLUA = 1
  ConsentPromptBehaviorAdmin = 5
  PromptOnSecureDesktop = 1
}
if ($stock.UacElevationMode -ne 'prompt-according-to-windows-policy') {
  throw 'Stock Windows UAC prompt policy was not detected.'
}

$uacDisabled = Get-BDAutoCompatibilityReport -TargetProfile $profile -RootPath $repoRoot -CapabilityOverrides @{
  EnableLUA = 0
  ConsentPromptBehaviorAdmin = 0
  PromptOnSecureDesktop = 0
}
if ($uacDisabled.UacElevationMode -ne 'uac-disabled') {
  throw 'Disabled UAC policy was not detected.'
}

Write-Host '[PASS] Reduced/custom Windows and UAC policy simulations'
