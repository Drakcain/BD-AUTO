$ErrorActionPreference = 'Stop'
$taskName = 'BetterDiscord Auto Repair Watchdog'
if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
  Write-Host 'ScheduledTasks PowerShell module is unavailable; no task removal was attempted.'
  exit 0
}
try {
  $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed scheduled task: $taskName"
  } else {
    Write-Host "Scheduled task not found: $taskName"
  }
} catch {
  Write-Warning "Scheduled task removal was unavailable: $_"
}
