# BD-AUTO

BD-AUTO installs BetterDiscord for Discord Stable, synchronizes a curated plugin/theme list, and repairs BetterDiscord after Discord updates.

Users download one file from GitHub Releases:

```text
BD-AUTO-Setup.exe
```

No PowerShell knowledge or manual file copying is required.

## What It Does

- Installs to `C:\Tools\BD-AUTO`.
- Downloads the latest official BetterDiscord CLI from `BetterDiscord/cli`.
- Verifies the CLI archive against BetterDiscord's published SHA-256 checksum.
- Installs or repairs BetterDiscord for Discord Stable.
- Downloads and enables the addons listed in `payload/addons.manifest.json`.
- Avoids duplicate plugin/theme source files.
- Creates a hidden scheduled task that checks once after sign-in and once after resume from sleep.
- Refreshes the checksum-verified official BetterDiscord CLI only when a repair is required.
- Closes Discord before a required repair and relaunches it afterward.
- Retains the three newest local repair backups.

There is no recurring five-minute poll and no background process that runs continuously.

## Install

1. Open the latest GitHub Release.
2. Download `BD-AUTO-Setup.exe`.
3. Run it and approve the Windows administrator prompt.
4. Wait for setup to install BetterDiscord and reopen Discord.

The EXE is currently unsigned. Windows SmartScreen may show **Windows protected your PC**. Select **More info**, verify that the file came from this repository's Releases page, and select **Run anyway**.

## Manual Repair

Use either shortcut created by setup:

- Desktop: **Repair BetterDiscord**
- Start Menu: **BD-AUTO > Repair BetterDiscord**

The repair shortcut runs the watchdog with `-ForceRepair -ReopenDiscord`.

## Uninstall

Use **Settings > Apps > Installed apps > BD-AUTO**, or use **BD-AUTO > Uninstall BD-AUTO** from the Start Menu.

Uninstall removes the scheduled task and `C:\Tools\BD-AUTO`. It does not delete Discord user data or `%APPDATA%\BetterDiscord`.

## Supported Configuration

- Windows 10/11 x64
- Discord Stable
- Internet access during setup and addon updates

PTB and Canary are not currently supported by the packaged installer.

## Build

See [BUILD.md](BUILD.md).

## Important Notice

BD-AUTO is not affiliated with Discord Inc. or BetterDiscord.

BetterDiscord is a third-party Discord client modification. Client modifications may violate Discord's Terms of Service and can stop working after Discord updates. Use this project at your own risk.

Third-party plugins and themes are downloaded from their respective upstream projects. Review `payload/addons.manifest.json` before installing or publishing a modified build.

## CODEX Did This

- Replaced the recurring five-minute poll with hidden sign-in and wake-event triggers.
- Added checksum verification for official BetterDiscord CLI downloads during setup and repair.
- Added deterministic add-on synchronization with duplicate pruning and atomic enable-state writes.
- Added Discord shutdown, relaunch, stabilization, and injection verification.
- Added repair backups with bounded retention.
- Added repository validation, secret scanning, Inno Setup packaging, and GitHub Actions releases.
