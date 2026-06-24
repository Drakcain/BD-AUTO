# BD-AUTO Installer And Build

BD-AUTO is installer-first for Windows distribution.

Current packaging target:

```text
dist\BD-AUTO-Setup.exe
```

Installed path target:

```text
C:\Tools\BD-AUTO
```

## Requirements

- Windows 10/11
- PowerShell 5.1 or later
- Inno Setup 6
- Git

Install Inno Setup with:

```powershell
winget install --id JRSoftware.InnoSetup -e
```

## Validation

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Repo.ps1
```

## Build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1
```

Expected output:

```text
dist\BD-AUTO-Setup.exe
```

The build script validates the repository, downloads the latest official BetterDiscord CLI archive, verifies it against BetterDiscord's published checksum file, stages it under ignored `build\`, and embeds it in the installer.

## Packaging Notes

- BD-AUTO is installer-first for normal users.
- GitHub Releases may also include `BD-AUTO-Setup.exe.sha256`, which is an optional manual verification file and not the installer.
- A portable source bundle can still be run from source with `Install-BD-AUTO.cmd`.
- The installer includes `LICENSE`, `INSTALL-NOTICE.txt`, `THIRD-PARTY-NOTICES.md`, `SIGNING.md`, and `VERSION`.
