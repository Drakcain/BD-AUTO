[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$SkipBdcliDownload,
  [switch]$SkipBetterDiscordInstall,
  [switch]$SkipAddonSync,
  [switch]$SkipTaskInstall,
  [switch]$SkipShortcuts,
  [switch]$NoLaunchDiscord
)

$ErrorActionPreference = 'Stop'

function Write-InstallLog {
  param([string]$Message, [string]$Level = 'INFO')
  $installLogDir = Join-Path $TargetRoot 'logs'
  New-Item -ItemType Directory -Force -Path $installLogDir | Out-Null
  $installLogPath = Join-Path $installLogDir ("installer-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
  $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
  Add-Content -LiteralPath $installLogPath -Value $line
  Write-Host $line
}

function Test-RunningAsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevate {
  $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
  foreach ($entry in $PSBoundParameters.GetEnumerator()) {
    if ($entry.Value -is [bool]) {
      if ($entry.Value) { $argList += "-$($entry.Key)" }
    } else {
      $argList += "-$($entry.Key)"
      $argList += "$($entry.Value)"
    }
  }
  Write-Host 'Elevation required. Relaunching installer as administrator...'
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList | Out-Null
  exit
}

function Get-BdcliPath {
  $targetBundle = Join-Path $TargetRoot 'bin\bdcli.exe'
  if (Test-Path -LiteralPath $targetBundle) { return $targetBundle }

  $cmd = Get-Command bdcli -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) { return $cmd.Source }

  $winGetPackages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
  if (Test-Path -LiteralPath $winGetPackages) {
    $candidate = Get-ChildItem -Path $winGetPackages -Filter 'betterdiscord.cli*' -Directory -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($candidate) {
      $exe = Join-Path $candidate.FullName 'bdcli.exe'
      if (Test-Path -LiteralPath $exe) { return $exe }
    }
  }

  $links = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\bdcli.exe'
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

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
      Write-InstallLog 'Attempting winget fallback install for BetterDiscord CLI.'
      & winget install --id betterdiscord.cli -e --source winget --accept-package-agreements --accept-source-agreements | Out-Host
      $bdcli = Get-BdcliPath
      if ($bdcli) {
        Copy-Item -LiteralPath $bdcli -Destination (Join-Path $binDir 'bdcli.exe') -Force
        Write-InstallLog "Copied winget-installed bdcli to $(Join-Path $binDir 'bdcli.exe')"
      }
    } else {
      throw
    }
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

  $runningDiscord = @(Get-Process -Name Discord,DiscordCanary,DiscordPTB -ErrorAction SilentlyContinue)
  $discordRoot = Join-Path $env:LOCALAPPDATA 'Discord'
  $updateProcesses = @(Get-Process -Name Update -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -and $_.Path.StartsWith($discordRoot, [System.StringComparison]::OrdinalIgnoreCase) }
    catch { $false }
  })
  $discordProcesses = @($runningDiscord + $updateProcesses | Sort-Object Id -Unique)
  if ($discordProcesses.Count -gt 0) {
    Write-InstallLog ('Stopping Discord before BetterDiscord install: {0}' -f (($discordProcesses | Select-Object -ExpandProperty Id) -join ', '))
    foreach ($proc in $discordProcesses) {
      try { $null = $proc.CloseMainWindow() } catch { }
    }
    Start-Sleep -Seconds 3
    foreach ($proc in $discordProcesses) {
      if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch { }
      }
    }
    Start-Sleep -Seconds 2
    $remaining = @($discordProcesses | Where-Object { Get-Process -Id $_.Id -ErrorAction SilentlyContinue })
    if ($remaining.Count -gt 0) {
      throw "Could not stop all Discord processes: $($remaining.Id -join ', ')"
    }
  }

  Write-InstallLog "Running BetterDiscord CLI install via $bdcli"
  & $bdcli install --channel stable 2>&1 | ForEach-Object { Write-Host $_ }
  $code = $LASTEXITCODE
  Write-InstallLog "bdcli install exit code: $code"
  if ($code -ne 0) {
    throw "bdcli install failed with exit code $code"
  }
}

function Start-Discord {
  if ($NoLaunchDiscord) {
    Write-InstallLog 'Discord launch skipped.'
    return
  }

  if (Get-Process -Name Discord -ErrorAction SilentlyContinue) {
    Write-InstallLog 'Discord is already running.'
    return
  }

  $updateExe = Join-Path $env:LOCALAPPDATA 'Discord\Update.exe'
  if (-not (Test-Path -LiteralPath $updateExe)) {
    throw "Discord launcher not found: $updateExe"
  }

  Write-InstallLog 'Launching Discord.'
  Start-Process -FilePath $updateExe -ArgumentList '--processStart Discord.exe' | Out-Null
  $deadline = (Get-Date).AddSeconds(30)
  while ((Get-Date) -lt $deadline) {
    if (Get-Process -Name Discord -ErrorAction SilentlyContinue) {
      Write-InstallLog 'Discord launched successfully.'
      return
    }
    Start-Sleep -Seconds 2
  }
  throw 'Discord did not start within 30 seconds.'
}

function Install-WatchdogTask {
  if ($SkipTaskInstall) {
    Write-InstallLog 'Scheduled task install skipped.'
    return
  }

  $taskScript = Join-Path $TargetRoot 'BetterDiscordWatchdog\Install-BetterDiscord-WatchdogTask.ps1'
  if (-not (Test-Path -LiteralPath $taskScript)) {
    throw "Task installer not found: $taskScript"
  }

  Write-InstallLog 'Installing BetterDiscord watchdog scheduled task.'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $taskScript | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "Scheduled task installer failed with exit code $LASTEXITCODE"
  }
}

function New-DesktopShortcut {
  if ($SkipShortcuts) {
    Write-InstallLog 'Shortcut creation skipped.'
    return
  }

  $shortcutDir = [Environment]::GetFolderPath('Desktop')
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

  Write-InstallLog 'Synchronizing curated BetterDiscord addons.'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $syncScript -ManifestPath $manifestPath -ActiveRoot (Join-Path $env:APPDATA 'BetterDiscord') -CacheRoot (Join-Path $TargetRoot 'BetterDiscord') -Prune | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "Addon sync failed with exit code $LASTEXITCODE"
  }
}

if (-not $DryRun -and -not $SkipTaskInstall -and -not (Test-RunningAsAdmin)) {
  Invoke-SelfElevate
}

$SourceRoot = Split-Path -Parent $PSCommandPath
$TargetRoot = 'C:\Tools\BD-AUTO'

New-Item -ItemType Directory -Force -Path $TargetRoot | Out-Null
Write-InstallLog "Starting BD-AUTO install from $SourceRoot to $TargetRoot"

if (-not $DryRun) {
  Copy-Bundle -SourceRoot $SourceRoot -DestinationRoot $TargetRoot
  New-Item -ItemType Directory -Force -Path (Join-Path $TargetRoot 'logs'), (Join-Path $TargetRoot 'backups'), (Join-Path $TargetRoot 'bin') | Out-Null
  $statePath = Join-Path $TargetRoot 'BetterDiscordWatchdog\state.json'
  if (-not (Test-Path -LiteralPath $statePath)) {
    '{}' | Set-Content -LiteralPath $statePath -Encoding UTF8
  }
  Ensure-BdcliBinary
  Install-BetterDiscord
  Sync-AddonManifest
  Install-WatchdogTask
  New-DesktopShortcut
  Start-Discord
  Write-InstallLog 'Install completed successfully.'
} else {
  Write-InstallLog 'DryRun enabled: bundle copy, CLI download, BetterDiscord install, addon sync, task install, shortcut creation, and Discord launch were skipped.'
}
