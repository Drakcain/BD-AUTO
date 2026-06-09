function Get-BDAutoAccountFromSid {
  param([string]$Sid)

  if ([string]::IsNullOrWhiteSpace($Sid)) { return $null }
  try {
    $sidObject = New-Object Security.Principal.SecurityIdentifier($Sid)
    return $sidObject.Translate([Security.Principal.NTAccount]).Value
  } catch {
    return $null
  }
}

function Get-BDAutoUserProfiles {
  $profiles = @()
  try {
    $profiles = @(Get-CimInstance Win32_UserProfile -ErrorAction Stop |
      Where-Object { $_.LocalPath -and -not $_.Special })
  } catch { }
  if ($profiles.Count -gt 0) { return $profiles }

  $profileList = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
  try {
    return @(Get-ChildItem -LiteralPath $profileList -ErrorAction Stop | ForEach-Object {
      $properties = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
      $path = [Environment]::ExpandEnvironmentVariables([string]$properties.ProfileImagePath)
      if ($path -and (Test-Path -LiteralPath $path)) {
        [pscustomobject]@{
          SID = $_.PSChildName
          LocalPath = $path
          Special = $false
        }
      }
    } | Where-Object { $_ })
  } catch {
    return @()
  }
}

function Get-BDAutoProfileByName {
  param([string]$UserName)

  if ([string]::IsNullOrWhiteSpace($UserName)) { return $null }
  $shortName = ($UserName -split '\\')[-1]
  $profiles = @(Get-BDAutoUserProfiles)

  foreach ($profile in $profiles) {
    $account = Get-BDAutoAccountFromSid -Sid $profile.SID
    if (
      $account -ieq $UserName -or
      ($account -and (($account -split '\\')[-1] -ieq $shortName)) -or
      ((Split-Path -Leaf $profile.LocalPath) -ieq $shortName)
    ) {
      return $profile
    }
  }
  return $null
}

function New-BDAutoProfileResult {
  param(
    [string]$ProfileRoot,
    [string]$UserName,
    [string]$UserSid,
    [string]$Source,
    [string]$RoamingAppData,
    [string]$LocalAppData
  )

  if ([string]::IsNullOrWhiteSpace($ProfileRoot)) {
    if ($LocalAppData) {
      $ProfileRoot = Split-Path -Parent (Split-Path -Parent $LocalAppData)
    } elseif ($RoamingAppData) {
      $ProfileRoot = Split-Path -Parent (Split-Path -Parent $RoamingAppData)
    }
  }
  if ([string]::IsNullOrWhiteSpace($RoamingAppData)) {
    $RoamingAppData = Join-Path $ProfileRoot 'AppData\Roaming'
  }
  if ([string]::IsNullOrWhiteSpace($LocalAppData)) {
    $LocalAppData = Join-Path $ProfileRoot 'AppData\Local'
  }

  $profile = Get-BDAutoUserProfiles |
    Where-Object { $_.LocalPath -ieq $ProfileRoot } |
    Select-Object -First 1
  if (-not $UserSid -and $profile) { $UserSid = $profile.SID }
  if (-not $UserName -and $UserSid) { $UserName = Get-BDAutoAccountFromSid -Sid $UserSid }
  if (-not $UserName) { $UserName = Split-Path -Leaf $ProfileRoot }

  return [pscustomobject]@{
    UserName = $UserName
    UserSid = $UserSid
    ProfileRoot = $ProfileRoot
    RoamingAppData = $RoamingAppData
    LocalAppData = $LocalAppData
    BetterDiscordRoot = Join-Path $RoamingAppData 'BetterDiscord'
    DiscordRoot = Join-Path $LocalAppData 'Discord'
    DetectionSource = $Source
  }
}

function Resolve-BDAutoTargetProfile {
  [CmdletBinding()]
  param(
    [string]$TargetUserName,
    [string]$TargetRoamingAppData,
    [string]$TargetLocalAppData
  )

  if ($TargetRoamingAppData -or $TargetLocalAppData) {
    $profileRoot = $null
    if ($TargetLocalAppData) {
      $profileRoot = Split-Path -Parent (Split-Path -Parent $TargetLocalAppData)
    } else {
      $profileRoot = Split-Path -Parent (Split-Path -Parent $TargetRoamingAppData)
    }
    return New-BDAutoProfileResult -ProfileRoot $profileRoot -UserName $TargetUserName `
      -Source 'explicit AppData override' -RoamingAppData $TargetRoamingAppData -LocalAppData $TargetLocalAppData
  }

  if ($TargetUserName) {
    $namedProfile = Get-BDAutoProfileByName -UserName $TargetUserName
    if (-not $namedProfile) { throw "Windows profile was not found for target user '$TargetUserName'." }
    return New-BDAutoProfileResult -ProfileRoot $namedProfile.LocalPath -UserName $TargetUserName `
      -UserSid $namedProfile.SID -Source 'explicit user override'
  }

  $discordProcesses = @()
  try {
    $discordProcesses = @(Get-CimInstance Win32_Process -Filter "Name='Discord.exe'" -ErrorAction Stop)
  } catch {
    $discordProcesses = @(Get-Process Discord -ErrorAction SilentlyContinue | ForEach-Object {
      [pscustomobject]@{
        ProcessId = $_.Id
        ExecutablePath = try { $_.Path } catch { $null }
      }
    })
  }
  foreach ($process in $discordProcesses) {
    $path = [string]$process.ExecutablePath
    if ($path -match '^(?<profile>.+)\\AppData\\Local\\Discord\\app-[^\\]+\\Discord\.exe$') {
      $owner = $null
      try { $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwner -ErrorAction Stop } catch { }
      $ownerName = if ($owner -and $owner.User) { "$($owner.Domain)\$($owner.User)" } else { $null }
      return New-BDAutoProfileResult -ProfileRoot $Matches.profile -UserName $ownerName `
        -Source "running Discord process $($process.ProcessId)"
    }
  }

  $explorerProcesses = @()
  try {
    $explorerProcesses = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop)
  } catch { }
  foreach ($process in $explorerProcesses) {
    $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwner -ErrorAction SilentlyContinue
    if (-not $owner -or -not $owner.User) { continue }
    $ownerName = "$($owner.Domain)\$($owner.User)"
    $profile = Get-BDAutoProfileByName -UserName $ownerName
    if ($profile -and (Test-Path -LiteralPath (Join-Path $profile.LocalPath 'AppData\Local\Discord\Update.exe'))) {
      return New-BDAutoProfileResult -ProfileRoot $profile.LocalPath -UserName $ownerName `
        -UserSid $profile.SID -Source "interactive Explorer process $($process.ProcessId)"
    }
  }

  $consoleUser = $null
  try { $consoleUser = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName } catch { }
  if (-not $consoleUser -and $env:USERDOMAIN -and $env:USERNAME) {
    $consoleUser = "$env:USERDOMAIN\$env:USERNAME"
  }
  if ($consoleUser) {
    $profile = Get-BDAutoProfileByName -UserName $consoleUser
    if ($profile -and (Test-Path -LiteralPath (Join-Path $profile.LocalPath 'AppData\Local\Discord\Update.exe'))) {
      return New-BDAutoProfileResult -ProfileRoot $profile.LocalPath -UserName $consoleUser `
        -UserSid $profile.SID -Source 'interactive console user'
    }
  }

  $discordProfiles = @(Get-BDAutoUserProfiles |
    Where-Object {
      $_.LocalPath -and
      -not $_.Special -and
      (Test-Path -LiteralPath (Join-Path $_.LocalPath 'AppData\Local\Discord\Update.exe'))
    })
  if ($discordProfiles.Count -eq 1) {
    return New-BDAutoProfileResult -ProfileRoot $discordProfiles[0].LocalPath -UserSid $discordProfiles[0].SID `
      -Source 'only Windows profile with Discord Stable'
  }
  if ($discordProfiles.Count -gt 1) {
    $paths = ($discordProfiles.LocalPath -join ', ')
    throw "Multiple Windows profiles contain Discord Stable. Specify -TargetUserName. Profiles: $paths"
  }

  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $currentProfile = Get-BDAutoUserProfiles |
    Where-Object { $_.SID -eq $currentIdentity.User.Value } |
    Select-Object -First 1
  if ($currentProfile) {
    return New-BDAutoProfileResult -ProfileRoot $currentProfile.LocalPath -UserName $currentIdentity.Name `
      -UserSid $currentIdentity.User.Value -Source 'current process identity fallback'
  }

  return New-BDAutoProfileResult -ProfileRoot $env:USERPROFILE -UserName $currentIdentity.Name `
    -UserSid $currentIdentity.User.Value -Source 'environment fallback' `
    -RoamingAppData $env:APPDATA -LocalAppData $env:LOCALAPPDATA
}

function Write-BDAutoTargetProfileLog {
  param(
    [Parameter(Mandatory = $true)]$Profile,
    [Parameter(Mandatory = $true)][scriptblock]$WriteLog
  )

  & $WriteLog "Target user: $($Profile.UserName)"
  & $WriteLog "Target SID: $($Profile.UserSid)"
  & $WriteLog "Target detection: $($Profile.DetectionSource)"
  & $WriteLog "Target Roaming AppData: $($Profile.RoamingAppData)"
  & $WriteLog "Target Local AppData: $($Profile.LocalAppData)"
  & $WriteLog "Active BetterDiscord path: $($Profile.BetterDiscordRoot)"
  & $WriteLog "Target Discord path: $($Profile.DiscordRoot)"
}

function Get-BDAutoDiscordProcessIds {
  param(
    [Parameter(Mandatory = $true)]$Profile
  )

  $processes = @()
  try {
    $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop |
      Where-Object { $_.Name -in @('Discord.exe', 'Update.exe') })
  } catch {
    $processes = @(Get-Process Discord, Update -ErrorAction SilentlyContinue | ForEach-Object {
      [pscustomobject]@{
        Name = "$($_.ProcessName).exe"
        ProcessId = $_.Id
        ParentProcessId = 0
        SessionId = $_.SessionId
        ExecutablePath = try { $_.Path } catch { $null }
      }
    })
  }
  $discordProcesses = @($processes | Where-Object Name -eq 'Discord.exe')
  $ids = New-Object System.Collections.Generic.HashSet[int]
  $discordTreeIds = New-Object System.Collections.Generic.HashSet[int]
  $targetSessionIds = New-Object System.Collections.Generic.HashSet[int]
  $discordById = @{}
  foreach ($process in $discordProcesses) {
    $discordById[[int]$process.ProcessId] = $process
  }

  foreach ($process in $discordProcesses) {
    $pathMatches = $false
    if ($process.ExecutablePath) {
      $pathMatches = $process.ExecutablePath.StartsWith(
        $Profile.DiscordRoot,
        [System.StringComparison]::OrdinalIgnoreCase
      )
    }

    $ownerMatches = $false
    if ($Profile.UserSid) {
      $ownerSid = $null
      try { $ownerSid = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction Stop } catch { }
      $ownerMatches = $ownerSid -and ($ownerSid.Sid -eq $Profile.UserSid)
    }

    if ($pathMatches -or $ownerMatches) {
      [void]$discordTreeIds.Add([int]$process.ProcessId)
      if ($pathMatches -and $null -ne $process.SessionId) {
        [void]$targetSessionIds.Add([int]$process.SessionId)
      }
      if ($discordById.ContainsKey([int]$process.ParentProcessId)) {
        [void]$discordTreeIds.Add([int]$process.ParentProcessId)
      }
    }
  }

  if ($targetSessionIds.Count -gt 0) {
    foreach ($process in $discordProcesses) {
      if ($null -ne $process.SessionId -and $targetSessionIds.Contains([int]$process.SessionId)) {
        [void]$discordTreeIds.Add([int]$process.ProcessId)
      }
    }
  }

  $added = $true
  while ($added) {
    $added = $false
    foreach ($process in $discordProcesses) {
      $processId = [int]$process.ProcessId
      $parentId = [int]$process.ParentProcessId
      if ($discordTreeIds.Contains($parentId) -and -not $discordTreeIds.Contains($processId)) {
        [void]$discordTreeIds.Add($processId)
        $added = $true
      }
    }
  }
  foreach ($processId in $discordTreeIds) {
    [void]$ids.Add($processId)
  }

  foreach ($process in ($processes | Where-Object Name -eq 'Update.exe')) {
    if (
      $process.ExecutablePath -and
      $process.ExecutablePath.StartsWith($Profile.DiscordRoot, [System.StringComparison]::OrdinalIgnoreCase)
    ) {
      [void]$ids.Add([int]$process.ProcessId)
    }
  }

  return @($ids)
}
