[CmdletBinding()]
param(
  [ValidatePattern('^\d+\.\d+\.\d+([.-][A-Za-z0-9.-]+)?$')]
  [string]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$compilerCandidates = @(
  (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
  'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
  'C:\Program Files\Inno Setup 6\ISCC.exe'
)
$compiler = $compilerCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $compiler) {
  throw 'Inno Setup 6 compiler was not found. See BUILD.md.'
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-Repo.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Repository validation failed.' }

$dist = Join-Path $RepoRoot 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
Remove-Item -LiteralPath (Join-Path $dist 'BD-AUTO-Setup.exe') -Force -ErrorAction SilentlyContinue

& $compiler "/DMyAppVersion=$Version" (Join-Path $RepoRoot 'installer\BD-AUTO.iss') | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE." }

$output = Join-Path $dist 'BD-AUTO-Setup.exe'
if (-not (Test-Path -LiteralPath $output)) { throw 'Installer output was not created.' }

$hash = Get-FileHash -LiteralPath $output -Algorithm SHA256
$hashLine = "$($hash.Hash)  BD-AUTO-Setup.exe"
[System.IO.File]::WriteAllText((Join-Path $dist 'BD-AUTO-Setup.exe.sha256'), $hashLine + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Built: $output"
Write-Host "SHA-256: $($hash.Hash)"
