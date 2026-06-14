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

winget is only a convenience for developers installing Inno Setup. The produced BD-AUTO installer does not require winget.

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
- original-user installer execution and target-profile propagation
- path-bound BetterDiscord CLI installation
- absence of logs, state, backups, secrets, and bundled executables
- required installer files
- scheduled-task trigger configuration
- bundled checksum-verified BetterDiscord CLI staging
- customized/stripped Windows compatibility reporting
- graceful manual fallback when Task Scheduler is unavailable
- source-aware addon version selection and BDFDB downgrade regression scenarios

## Compile

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1
```

Expected output:

```text
dist\BD-AUTO-Setup.exe
```

The build script validates the repository, downloads the latest official BetterDiscord CLI archive, verifies it against BetterDiscord's published checksum file, stages it under ignored `build\`, and embeds it in the installer. The executable is never committed to source.

## Test Locally

1. Create a Windows VM or test account with Discord Stable installed.
2. Run `dist\BD-AUTO-Setup.exe`.
3. Confirm BetterDiscord appears in Discord settings.
4. Confirm 16 plugins and 2 themes are present.
5. Confirm Task Scheduler contains `BetterDiscord Auto Repair Watchdog`, or confirm `runtime\task-status.json` reports a graceful manual-only fallback.
6. Confirm the task has only logon and event triggers, with no recurring time trigger.
7. Simulate a repair using the **Repair BetterDiscord** shortcut.
8. Confirm setup displays `INSTALL-NOTICE.txt` and installs `THIRD-PARTY-NOTICES.md`.
9. Open **BD-AUTO > Third-Party Notices** from the Start Menu.
10. Confirm `runtime\target-profile.json` identifies the user that runs Discord.
11. Confirm the task principal and action arguments target that same user and AppData.
12. Uninstall BD-AUTO and verify the task is removed.
13. Confirm `runtime\compatibility.json` and `runtime\install-summary.txt` accurately describe the machine.
14. Confirm the installer still succeeds when winget is unavailable.
15. Run the addon audit and confirm no installed addon is selected for downgrade.
16. Confirm `runtime\addon-audit.json` records installed, cached, and upstream versions.

## GitHub Release

Pushing a tag matching `v*` runs `.github/workflows/build.yml`, builds the EXE, and creates a GitHub Release:

```powershell
git tag v1.1.0
git push origin v1.1.0
```

## Do Not Commit

- `dist/`
- logs
- `state.json`
- repair backups
- downloaded `bdcli.exe`
- addon cache files
- credentials, tokens, or personal configuration
