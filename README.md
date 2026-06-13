# BD-AUTO

BD-AUTO installs BetterDiscord for Discord Stable, synchronizes a curated plugin/theme list, and repairs BetterDiscord after Discord updates.

Users download one file from GitHub Releases:

```text
BD-AUTO-Setup.exe
```

No PowerShell knowledge or manual file copying is required.

## What It Does

- Installs to `C:\Tools\BD-AUTO`.
- Bundles the official BetterDiscord CLI during the release build after verifying BetterDiscord's published SHA-256 checksum.
- Uses the bundled CLI first, so winget and Microsoft Store/App Installer are not required.
- Installs or repairs BetterDiscord for Discord Stable.
- Downloads and enables the addons listed in `payload/addons.manifest.json`.
- Avoids duplicate plugin/theme source files.
- Creates a hidden scheduled task that checks once after sign-in and once after resume from sleep when Task Scheduler supports it.
- Keeps desktop and Start Menu repair shortcuts available when scheduled automation is disabled or stripped.
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

The UAC prompt is expected because setup installs to `C:\Tools` and configures optional scheduled automation. Code signing can improve publisher trust and SmartScreen reputation, but it does not remove UAC. See [SIGNING.md](SIGNING.md).

## Manual Repair

Use either shortcut created by setup:

- Desktop: **Repair BetterDiscord**
- Start Menu: **BD-AUTO > Repair BetterDiscord**

The repair shortcut runs the watchdog with `-ForceRepair -RestoreStash -ReopenDiscord`.
Windows may request UAC approval when a repair must stop an elevated Discord process or modify an installation that requires administrator rights.

The Start Menu also contains:

- **BD-AUTO Logs**
- **View BD-AUTO Status**
- **Installation Summary**
- **Third-Party Notices**
- **Signing and Windows Warnings**

## How To Check Your Version

Use any of these:

- Start Menu: **BD-AUTO > View BD-AUTO Status**
- `C:\Tools\BD-AUTO\VERSION`
- `C:\Tools\BD-AUTO\BD-AUTO-STATUS.txt`
- `C:\Tools\BD-AUTO\runtime\installed-version.json`
- PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Tools\BD-AUTO\BetterDiscordWatchdog\BetterDiscord-Watchdog.ps1" -Status
```

## Troubleshooting Add-On Toggles

If BetterDiscord appears in Discord but the Plugins or Themes page is empty:

1. Exit Discord completely.
2. Run **Repair BetterDiscord** from the desktop or Start Menu.
3. Reopen Discord and check **User Settings > BetterDiscord > Plugins/Themes**.

BD-AUTO records the Windows user and exact paths it targeted in:

```text
C:\Tools\BD-AUTO\runtime\target-profile.json
C:\Tools\BD-AUTO\runtime\compatibility.json
C:\Tools\BD-AUTO\runtime\install-summary.txt
C:\Tools\BD-AUTO\logs\installer-YYYYMMDD.log
C:\Tools\BD-AUTO\runtime\logs\watchdog-YYYYMMDD.log
```

The active files must be under the same Windows profile that runs Discord:

```text
<UserProfile>\AppData\Roaming\BetterDiscord\plugins
<UserProfile>\AppData\Roaming\BetterDiscord\themes
```

Setup is intentionally bound to one Discord Windows profile. If UAC requests credentials for a different administrator account, BD-AUTO still performs Discord, BetterDiscord, add-on, and relaunch work as the original desktop user, then registers the elevated scheduled task for that user's SID.

### Scheduled Task Failed

Task Scheduler is optional. If Windows reports that the task could not be installed:

1. Use **Repair BetterDiscord** after a Discord update.
2. Review `C:\Tools\BD-AUTO\runtime\task-status.json`.
3. On customized Windows builds, verify that the **Task Scheduler** service and ScheduledTasks PowerShell module are enabled.

The installer does not fail or remove a healthy BetterDiscord installation solely because scheduled automation is unavailable.

### Customized Or Stripped Windows

BD-AUTO supports stock Windows 10/11 x64 and provides best-effort support for Ghost Spectre and other customized builds. It detects missing management, security, and scheduling components and records them in `runtime\compatibility.json`.

BD-AUTO does not re-enable stripped services or bypass Windows security settings. Core installation and the manual repair shortcut require Windows PowerShell, administrator approval, Discord Stable, and the bundled BetterDiscord CLI. Wake and sign-in automation depends on Task Scheduler.

For an ambiguous multi-user PC, run a targeted repair:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Tools\BD-AUTO\BetterDiscordWatchdog\BetterDiscord-Watchdog.ps1" -ForceRepair -ReopenDiscord -TargetUserName "WindowsUserName"
```

## Uninstall

Use **Settings > Apps > Installed apps > BD-AUTO**, or use **BD-AUTO > Uninstall BD-AUTO** from the Start Menu.

Uninstall removes the scheduled task and `C:\Tools\BD-AUTO`. It does not delete Discord user data or `%APPDATA%\BetterDiscord`.

## Supported Configuration

- Windows 10/11 x64
- Discord Stable
- Internet access during setup and addon updates
- Windows PowerShell 5.1 or later

winget, Microsoft Store, Defender, SmartScreen, and Task Scheduler are not core installation dependencies. Missing security components are reported, not installed or bypassed.

PTB and Canary are not currently supported by the packaged installer.

## Build

See [BUILD.md](BUILD.md).

## Important Notice

BD-AUTO is independent automation glue. It is not affiliated with, authorized by, sponsored by, or endorsed by Discord Inc., BetterDiscord, GitHub, Microsoft, JRSoftware, or any plugin/theme author.

BetterDiscord is a third-party Discord client modification. Discord's current Terms restrict unauthorized software designed to modify its services. Installing or using BetterDiscord or BD-AUTO may violate Discord's terms or policies, can stop working after Discord updates, and may expose a user to service or account enforcement. Use this project at your own risk.

BD-AUTO does not include Discord and does not bypass authentication, security controls, subscriptions, paid features, or account restrictions.

Third-party plugins and themes are not embedded in the setup executable. They are downloaded from pinned upstream locations during installation and remain the property of their original authors.

## Credits And Licensing

- BetterDiscord and the BetterDiscord CLI are created and maintained by the [BetterDiscord project](https://github.com/BetterDiscord).
- The official graphical [BetterDiscord Installer](https://github.com/BetterDiscord/Installer) is a separate manual alternative and is not bundled or invoked by BD-AUTO.
- The Windows setup is compiled with [Inno Setup](https://jrsoftware.org/isinfo.php), created by Jordan Russell with portions by Martijn Laan.
- Releases are built with [GitHub Actions](https://docs.github.com/actions).
- Plugin and theme authors are credited individually in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

The repository's [MIT license](LICENSE) applies only to BD-AUTO's original scripts, documentation, manifest, workflow, and installer configuration. It does not relicense Discord, BetterDiscord, the BetterDiscord CLI, the BetterDiscord Installer, Inno Setup, GitHub Actions, or any plugin/theme.

Three configured add-on repositories currently have no detected license. They are identified explicitly in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). Absence of a license does not grant redistribution rights.

## CODEX Did This

- Replaced the recurring five-minute poll with hidden sign-in and wake-event triggers.
- Added checksum verification for official BetterDiscord CLI downloads during setup and repair.
- Added deterministic add-on synchronization with duplicate pruning and atomic enable-state writes.
- Added Discord shutdown, relaunch, stabilization, and injection verification.
- Added repair backups with bounded retention.
- Added repository validation, secret scanning, Inno Setup packaging, and GitHub Actions releases.
- Added a compatibility preflight, self-contained verified CLI packaging, graceful scheduled-task fallback, and installation summaries for stock and customized Windows builds.
