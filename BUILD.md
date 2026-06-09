# Building BD-AUTO

## Requirements

- Windows 10/11
- PowerShell 5.1 or later
- Inno Setup 6
- Git

Install Inno Setup with:

```powershell
winget install --id JRSoftware.InnoSetup -e
```

## Validate

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Repo.ps1
```

The validation checks:

- PowerShell syntax
- manifest uniqueness and HTTPS sources
- manifest author, project, and license attribution
- complete third-party notice coverage for every configured add-on
- absence of logs, state, backups, secrets, and bundled executables
- required installer files
- scheduled-task trigger configuration

## Compile

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1 -Version 1.0.0
```

Expected output:

```text
dist\BD-AUTO-Setup.exe
```

The build script validates the repository before compiling.

## Test Locally

1. Create a Windows VM or test account with Discord Stable installed.
2. Run `dist\BD-AUTO-Setup.exe`.
3. Confirm BetterDiscord appears in Discord settings.
4. Confirm 16 plugins and 2 themes are present.
5. Confirm Task Scheduler contains `BetterDiscord Auto Repair Watchdog`.
6. Confirm the task has only logon and event triggers, with no recurring time trigger.
7. Simulate a repair using the **Repair BetterDiscord** shortcut.
8. Confirm setup displays `INSTALL-NOTICE.txt` and installs `THIRD-PARTY-NOTICES.md`.
9. Open **BD-AUTO > Third-Party Notices** from the Start Menu.
10. Uninstall BD-AUTO and verify the task is removed.

## GitHub Release

Pushing a tag matching `v*` runs `.github/workflows/build.yml`, builds the EXE, and creates a GitHub Release:

```powershell
git tag v1.0.0
git push origin v1.0.0
```

## Do Not Commit

- `dist/`
- logs
- `state.json`
- repair backups
- downloaded `bdcli.exe`
- addon cache files
- credentials, tokens, or personal configuration
