$ErrorActionPreference = 'Stop'
$taskName = 'BetterDiscord Auto Repair Watchdog'
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
  Write-Host "Removed scheduled task: $taskName"
} else {
  Write-Host "Scheduled task not found: $taskName"
}
