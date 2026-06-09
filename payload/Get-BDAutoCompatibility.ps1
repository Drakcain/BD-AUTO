function Test-BDAutoAdministrator {
  try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch {
    return $false
  }
}

function Get-BDAutoServiceSnapshot {
  param([string]$Name)

  try {
    $service = Get-Service -Name $Name -ErrorAction Stop
    return [pscustomobject]@{
      Present = $true
      Status = [string]$service.Status
      StartType = [string]$service.StartType
    }
  } catch {
    return [pscustomobject]@{
      Present = $false
      Status = 'Unavailable'
      StartType = 'Unknown'
    }
  }
}

function Get-BDAutoInteractiveUser {
  try {
    $explorer = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop |
      Select-Object -First 1
    if ($explorer) {
      $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner -ErrorAction Stop
      if ($owner -and $owner.User) { return "$($owner.Domain)\$($owner.User)" }
    }
  } catch { }

  try {
    $consoleUser = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
    if ($consoleUser) { return $consoleUser }
  } catch { }

  if ($env:USERDOMAIN -and $env:USERNAME) {
    return "$env:USERDOMAIN\$env:USERNAME"
  }
  return $env:USERNAME
}

function Get-BDAutoCompatibilityReport {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$TargetProfile,
    [Parameter(Mandatory = $true)][string]$RootPath,
    [hashtable]$CapabilityOverrides
  )

  $currentVersion = @{}
  try {
    $currentVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
  } catch { }

  $osCaption = $null
  $osVersion = $null
  $osBuild = $null
  $osArchitecture = $env:PROCESSOR_ARCHITECTURE
  $cimAvailable = $false
  try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cimAvailable = $true
    $osCaption = [string]$os.Caption
    $osVersion = [string]$os.Version
    $osBuild = [string]$os.BuildNumber
    $osArchitecture = [string]$os.OSArchitecture
  } catch { }

  if (-not $osCaption) { $osCaption = [string]$currentVersion.ProductName }
  if (-not $osVersion) { $osVersion = [Environment]::OSVersion.Version.ToString() }
  if (-not $osBuild) {
    $osBuild = if ($currentVersion.CurrentBuildNumber) {
      [string]$currentVersion.CurrentBuildNumber
    } else {
      [string][Environment]::OSVersion.Version.Build
    }
  }

  $taskService = Get-BDAutoServiceSnapshot -Name 'Schedule'
  $defenderService = Get-BDAutoServiceSnapshot -Name 'WinDefend'
  $securityHealthService = Get-BDAutoServiceSnapshot -Name 'SecurityHealthService'
  $taskCmdletsPresent = [bool](
    (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue) -and
    (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)
  )
  $taskSchedulerAvailable = (
    $taskService.Present -and
    $taskService.StartType -ne 'Disabled' -and
    $taskCmdletsPresent
  )

  $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
  $bundledBdcli = Join-Path $RootPath 'bin\bdcli.exe'
  $guiFallback = @(
    (Join-Path $RootPath 'bin\BetterDiscord-Windows.exe'),
    (Join-Path $RootPath 'BetterDiscord-Windows.exe')
  ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

  $brandingText = @(
    $osCaption,
    $currentVersion.ProductName,
    $currentVersion.EditionID,
    $currentVersion.DisplayVersion,
    $currentVersion.RegisteredOrganization,
    $currentVersion.RegisteredOwner
  ) -join ' '
  if ($CapabilityOverrides) {
    if ($CapabilityOverrides.ContainsKey('CimAvailable')) {
      $cimAvailable = [bool]$CapabilityOverrides.CimAvailable
    }
    if ($CapabilityOverrides.ContainsKey('TaskServicePresent')) {
      $taskService.Present = [bool]$CapabilityOverrides.TaskServicePresent
    }
    if ($CapabilityOverrides.ContainsKey('TaskServiceStatus')) {
      $taskService.Status = [string]$CapabilityOverrides.TaskServiceStatus
    }
    if ($CapabilityOverrides.ContainsKey('TaskServiceStartType')) {
      $taskService.StartType = [string]$CapabilityOverrides.TaskServiceStartType
    }
    if ($CapabilityOverrides.ContainsKey('TaskCmdletsPresent')) {
      $taskCmdletsPresent = [bool]$CapabilityOverrides.TaskCmdletsPresent
    }
    if ($CapabilityOverrides.ContainsKey('DefenderServicePresent')) {
      $defenderService.Present = [bool]$CapabilityOverrides.DefenderServicePresent
    }
    if ($CapabilityOverrides.ContainsKey('SecurityHealthServicePresent')) {
      $securityHealthService.Present = [bool]$CapabilityOverrides.SecurityHealthServicePresent
    }
    if ($CapabilityOverrides.ContainsKey('BrandingText')) {
      $brandingText = [string]$CapabilityOverrides.BrandingText
    }
  }
  $taskSchedulerAvailable = (
    $taskService.Present -and
    $taskService.StartType -ne 'Disabled' -and
    $taskCmdletsPresent
  )
  $brandingMatch = [regex]::Match(
    $brandingText,
    '(?i)\b(ghost\s*spectre|superlite|compact|tiny11|atlas\s*os|revi\s*os)\b'
  )

  $reducedIndicators = New-Object System.Collections.Generic.List[string]
  if (-not $cimAvailable) { $reducedIndicators.Add('Windows management/CIM unavailable') }
  if (-not $taskService.Present) { $reducedIndicators.Add('Task Scheduler service unavailable') }
  elseif ($taskService.StartType -eq 'Disabled') { $reducedIndicators.Add('Task Scheduler service disabled') }
  if (-not $taskCmdletsPresent) { $reducedIndicators.Add('ScheduledTasks PowerShell module unavailable') }
  if (-not $defenderService.Present -and -not $securityHealthService.Present) {
    $reducedIndicators.Add('Windows security services unavailable')
  }

  $customIndicators = New-Object System.Collections.Generic.List[string]
  if ($brandingMatch.Success) {
    $customIndicators.Add("custom Windows branding: $($brandingMatch.Value)")
  }
  foreach ($indicator in $reducedIndicators) { $customIndicators.Add($indicator) }
  $customWindowsSuspected = $brandingMatch.Success -or $reducedIndicators.Count -ge 2

  return [pscustomobject]@{
    GeneratedAt = (Get-Date).ToString('o')
    WindowsCaption = $osCaption
    WindowsVersion = $osVersion
    WindowsBuild = $osBuild
    WindowsDisplayVersion = [string]$currentVersion.DisplayVersion
    WindowsEdition = [string]$currentVersion.EditionID
    WindowsArchitecture = $osArchitecture
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    ProcessElevated = Test-BDAutoAdministrator
    CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    InteractiveUser = Get-BDAutoInteractiveUser
    TargetUser = $TargetProfile.UserName
    TargetUserSid = $TargetProfile.UserSid
    TargetRoamingAppData = $TargetProfile.RoamingAppData
    TargetLocalAppData = $TargetProfile.LocalAppData
    DiscordRoot = $TargetProfile.DiscordRoot
    BetterDiscordRoot = $TargetProfile.BetterDiscordRoot
    CimAvailable = $cimAvailable
    TaskSchedulerServicePresent = $taskService.Present
    TaskSchedulerServiceStatus = $taskService.Status
    TaskSchedulerServiceStartType = $taskService.StartType
    ScheduledTaskCmdletsPresent = $taskCmdletsPresent
    TaskSchedulerAvailable = $taskSchedulerAvailable
    BundledBdcliPresent = Test-Path -LiteralPath $bundledBdcli
    BundledBdcliPath = $bundledBdcli
    WingetPresent = [bool]$winget
    WingetPath = if ($winget) { $winget.Source } else { $null }
    GuiFallbackPresent = [bool]$guiFallback
    GuiFallbackPath = [string]$guiFallback
    DefenderServicePresent = $defenderService.Present
    DefenderServiceStatus = $defenderService.Status
    SecurityHealthServicePresent = $securityHealthService.Present
    CustomWindowsSuspected = $customWindowsSuspected
    CustomWindowsIndicators = @($customIndicators)
  }
}

function Write-BDAutoCompatibilityLog {
  param(
    [Parameter(Mandatory = $true)]$Report,
    [Parameter(Mandatory = $true)][scriptblock]$WriteLog
  )

  & $WriteLog "Compatibility: Windows=$($Report.WindowsCaption), version=$($Report.WindowsVersion), build=$($Report.WindowsBuild), edition=$($Report.WindowsEdition)"
  & $WriteLog "Compatibility: PowerShell=$($Report.PowerShellVersion), elevated=$($Report.ProcessElevated), CIM=$($Report.CimAvailable)"
  & $WriteLog "Compatibility: current user=$($Report.CurrentUser), interactive user=$($Report.InteractiveUser), target user=$($Report.TargetUser)"
  & $WriteLog "Compatibility: Task Scheduler available=$($Report.TaskSchedulerAvailable), service=$($Report.TaskSchedulerServiceStatus)/$($Report.TaskSchedulerServiceStartType), cmdlets=$($Report.ScheduledTaskCmdletsPresent)"
  & $WriteLog "Compatibility: bundled bdcli=$($Report.BundledBdcliPresent), winget optional=$($Report.WingetPresent), GUI fallback=$($Report.GuiFallbackPresent)"
  & $WriteLog "Compatibility: Defender service=$($Report.DefenderServicePresent)/$($Report.DefenderServiceStatus), SecurityHealth=$($Report.SecurityHealthServicePresent)"
  if ($Report.CustomWindowsSuspected) {
    & $WriteLog ("This Windows build appears customized or stripped. Core repair remains available; optional scheduled automation depends on enabled Windows components. Indicators: {0}" -f ($Report.CustomWindowsIndicators -join '; ')) 'WARN'
  }
}

function Save-BDAutoCompatibilityReport {
  param(
    [Parameter(Mandatory = $true)]$Report,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $directory = Split-Path -Parent $Path
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
  [System.IO.File]::WriteAllText(
    $Path,
    ($Report | ConvertTo-Json -Depth 6),
    (New-Object System.Text.UTF8Encoding($false))
  )
}
