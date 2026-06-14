# Third-Party Notices

Last reviewed: June 14, 2026

BD-AUTO is independent automation glue. It installs and repairs BetterDiscord, synchronizes a user-selected set of third-party add-ons, and packages that automation as a Windows installer. BD-AUTO does not claim ownership of Discord, BetterDiscord, the BetterDiscord CLI, the BetterDiscord Installer, Inno Setup, GitHub Actions, or any plugin or theme.

The MIT license in this repository applies only to BD-AUTO's original scripts, documentation, manifest, workflow, and installer configuration. Third-party software and content remain subject to their own copyright, license, trademark, and terms-of-service requirements.

This file is an attribution and disclosure record. It is not legal advice and does not grant rights beyond the applicable licenses.

## No Affiliation

BD-AUTO is not affiliated with, authorized by, sponsored by, or endorsed by Discord Inc., BetterDiscord, GitHub, Microsoft, JRSoftware, or any plugin/theme author listed below.

Discord and related names, software, and trademarks belong to Discord Inc. and its applicable affiliates or licensors. BD-AUTO does not include Discord. Users must obtain Discord separately and remain responsible for complying with [Discord's Terms of Service](https://discord.com/terms).

Discord's current Terms restrict unauthorized software designed to modify its services. BetterDiscord is a third-party client modification, so installing or using BetterDiscord or BD-AUTO may violate Discord's terms or policies and may expose a user to service or account enforcement. Use is at the user's own risk.

BD-AUTO does not bypass authentication, security controls, subscriptions, paid features, or account restrictions.

## Core Projects and Build Tools

### BetterDiscord

- Project: [BetterDiscord/BetterDiscord](https://github.com/BetterDiscord/BetterDiscord)
- Website and documentation: [betterdiscord.app](https://betterdiscord.app/) and [docs.betterdiscord.app](https://docs.betterdiscord.app/)
- License: [Apache License 2.0](https://github.com/BetterDiscord/BetterDiscord/blob/development/LICENSE)
- Role: The third-party Discord client modification that BD-AUTO installs, verifies, and repairs.
- Distribution: BetterDiscord is downloaded by the official BetterDiscord tooling; it is not stored in this repository or embedded in the BD-AUTO setup payload.

### BetterDiscord CLI

- Project: [BetterDiscord/cli](https://github.com/BetterDiscord/cli)
- Documentation: [BetterDiscord CLI guide](https://docs.betterdiscord.app/users/guides/cli)
- License: [Apache License 2.0](https://github.com/BetterDiscord/cli/blob/main/LICENSE)
- Role: Official command-line installer used by BD-AUTO for BetterDiscord installation and repair.
- Distribution: The release build downloads the CLI from the official GitHub release, verifies BetterDiscord's published checksum, and embeds that verified binary in the setup payload. Runtime download is a checksum-verified fallback only when no usable local CLI exists.

### BetterDiscord Installer

- Project: [BetterDiscord/Installer](https://github.com/BetterDiscord/Installer)
- License: [MIT License](https://github.com/BetterDiscord/Installer/blob/development/LICENSE)
- Role: Official graphical installer and manual recovery alternative.
- Distribution: The BetterDiscord Installer is not bundled, downloaded, or invoked by BD-AUTO.

### Inno Setup

- Website: [JRSoftware Inno Setup](https://jrsoftware.org/isinfo.php)
- License: [Inno Setup License](https://jrsoftware.org/files/is/license.txt)
- Credits: Copyright (C) 1997-2026 Jordan Russell. Portions Copyright (C) 2000-2026 Martijn Laan.
- Role: Compiles the Windows setup executable.
- Distribution: The Inno Setup compiler is a build-time dependency. The generated installer uses the Inno Setup installation engine.
- Commercial use: Current BD-AUTO releases are produced as a non-commercial project. Anyone monetizing BD-AUTO or a derivative should review JRSoftware's current commercial licensing terms and obtain any required license.

### GitHub Actions

- Documentation: [GitHub Actions](https://docs.github.com/actions)
- Workflow actions: [actions/checkout](https://github.com/actions/checkout) and [actions/upload-artifact](https://github.com/actions/upload-artifact), both under their respective MIT licenses.
- Role: Builds and publishes BD-AUTO release artifacts.
- Distribution: GitHub Actions and its runner are build services and are not included in the installed product.

### Microsoft Windows and PowerShell

- Role: BD-AUTO uses Windows PowerShell, Task Scheduler, and standard Windows process-management facilities already provided by Windows.
- Distribution: Windows and PowerShell are not distributed by BD-AUTO. Microsoft product names are used only to describe compatibility and required system components.

## Add-On Distribution Model

BD-AUTO's public repository and setup executable do not contain plugin or theme source files. `payload/addons.manifest.json` documents HTTPS locations in the authors' upstream repositories. During setup, each user's computer downloads the selected files directly, validates the declared add-on metadata, and compares installed, upstream, and cached versions. Manifest versions are reviewed baselines, not instructions to downgrade a newer installed file.

This design does not transfer ownership or grant additional rights. Each add-on remains subject to its upstream license. A public repository with no detected license does not mean the work is public domain or freely redistributable; ordinary copyright restrictions apply unless the author grants permission.

Do not redistribute BD-AUTO's generated add-on cache or a populated BetterDiscord plugin/theme directory without separately satisfying every applicable upstream license.

## Curated Plugins

| File | Name | Author credit from file/repository | Version | Upstream | License detected |
| --- | --- | --- | --- | --- | --- |
| `0BDFDB.plugin.js` | BDFDB | DevilBro | 4.5.4 | [mwittrien/BetterDiscordAddons](https://github.com/mwittrien/BetterDiscordAddons) | [GPL-2.0](https://github.com/mwittrien/BetterDiscordAddons/blob/master/LICENSE) |
| `BetterFriendList.plugin.js` | BetterFriendList | DevilBro | 1.7.1 | [mwittrien/BetterDiscordAddons](https://github.com/mwittrien/BetterDiscordAddons) | [GPL-2.0](https://github.com/mwittrien/BetterDiscordAddons/blob/master/LICENSE) |
| `BetterNsfwTag.plugin.js` | BetterNsfwTag | DevilBro | 1.3.3 | [mwittrien/BetterDiscordAddons](https://github.com/mwittrien/BetterDiscordAddons) | [GPL-2.0](https://github.com/mwittrien/BetterDiscordAddons/blob/master/LICENSE) |
| `BetterVolume.plugin.js` | BetterVolume | Zerthox | 3.2.4 | [Zerthox/BetterDiscord-Plugins](https://github.com/Zerthox/BetterDiscord-Plugins) | [MIT](https://github.com/Zerthox/BetterDiscord-Plugins/blob/master/LICENSE) |
| `CallTimeCounter.plugin.js` | CallTimeCounter | QWERT, KingGamingYT; repository credits Rasync as original creator and states maintenance by the BetterDiscord Team | 1.0.2 | [KingGamingYT/CallTimeCounter](https://github.com/KingGamingYT/CallTimeCounter) | No license detected |
| `GameActivityToggle.plugin.js` | GameActivityToggle | DevilBro | 1.4.0 | [mwittrien/BetterDiscordAddons](https://github.com/mwittrien/BetterDiscordAddons) | [GPL-2.0](https://github.com/mwittrien/BetterDiscordAddons/blob/master/LICENSE) |
| `JumpToTop.plugin.js` | JumpToTop | SnappyCreeper | 1.0.6 | [snappycreeper/BetterDiscordPlugins](https://github.com/snappycreeper/BetterDiscordPlugins) | No license detected |
| `MoreRoleColors.plugin.js` | MoreRoleColors | DaddyBoard | 2.0.15 | [DaddyBoard/BD-Plugins](https://github.com/DaddyBoard/BD-Plugins) | No license detected |
| `OnlineFriendCount.plugin.js` | OnlineFriendCount | Zerthox | 3.3.2 | [Zerthox/BetterDiscord-Plugins](https://github.com/Zerthox/BetterDiscord-Plugins) | [MIT](https://github.com/Zerthox/BetterDiscord-Plugins/blob/master/LICENSE) |
| `ReadAllNotificationsButton.plugin.js` | ReadAllNotificationsButton | DevilBro | 1.8.5 | [mwittrien/BetterDiscordAddons](https://github.com/mwittrien/BetterDiscordAddons) | [GPL-2.0](https://github.com/mwittrien/BetterDiscordAddons/blob/master/LICENSE) |
| `ServerCounter.plugin.js` | ServerCounter | DevilBro | 1.1.1 | [mwittrien/BetterDiscordAddons](https://github.com/mwittrien/BetterDiscordAddons) | [GPL-2.0](https://github.com/mwittrien/BetterDiscordAddons/blob/master/LICENSE) |
| `ServerDetails.plugin.js` | ServerDetails | DevilBro | 1.3.6 | [mwittrien/BetterDiscordAddons](https://github.com/mwittrien/BetterDiscordAddons) | [GPL-2.0](https://github.com/mwittrien/BetterDiscordAddons/blob/master/LICENSE) |
| `ShowBadgesInChat.plugin.js` | ShowBadgesInChat | DevilBro | 2.1.6 | [mwittrien/BetterDiscordAddons](https://github.com/mwittrien/BetterDiscordAddons) | [GPL-2.0](https://github.com/mwittrien/BetterDiscordAddons/blob/master/LICENSE) |
| `StaffTag.plugin.js` | StaffTag | DevilBro | 1.7.4 | [mwittrien/BetterDiscordAddons](https://github.com/mwittrien/BetterDiscordAddons) | [GPL-2.0](https://github.com/mwittrien/BetterDiscordAddons/blob/master/LICENSE) |
| `Translator.plugin.js` | Translator | DevilBro | 2.8.2 | [mwittrien/BetterDiscordAddons](https://github.com/mwittrien/BetterDiscordAddons) | [GPL-2.0](https://github.com/mwittrien/BetterDiscordAddons/blob/master/LICENSE) |
| `WriteUpperCase.plugin.js` | WriteUpperCase | DevilBro | 1.4.6 | [mwittrien/BetterDiscordAddons](https://github.com/mwittrien/BetterDiscordAddons) | [GPL-2.0](https://github.com/mwittrien/BetterDiscordAddons/blob/master/LICENSE) |

## Curated Themes

| File | Name | Author credit from file/repository | Version | Upstream | License detected |
| --- | --- | --- | --- | --- | --- |
| `amoled-cord.theme.css` | AMOLED-Cord | LuckFire | 5.0.11 | [LuckFire/amoled-cord](https://github.com/LuckFire/amoled-cord) | [MIT](https://github.com/LuckFire/amoled-cord/blob/main/LICENSE) |
| `EmojiReplace.theme.css` | EmojiReplace | DevilBro | 1.0.0 | [mwittrien/BetterDiscordAddons](https://github.com/mwittrien/BetterDiscordAddons) | [GPL-2.0](https://github.com/mwittrien/BetterDiscordAddons/blob/master/LICENSE) |

## No-License-Detected Review

As of June 14, 2026, GitHub did not detect a license file for these upstream repositories:

- [KingGamingYT/CallTimeCounter](https://github.com/KingGamingYT/CallTimeCounter)
- [snappycreeper/BetterDiscordPlugins](https://github.com/snappycreeper/BetterDiscordPlugins)
- [DaddyBoard/BD-Plugins](https://github.com/DaddyBoard/BD-Plugins)

BD-AUTO credits these authors and downloads their files from their own public repositories, but that is not a substitute for an express license. Before commercial distribution, mirroring, bundling, or redistribution of populated add-on files, obtain permission or remove those entries.

## Corrections

Attribution can change as projects move or authors update metadata. If a credit or license classification is incorrect, open an issue with the upstream evidence needed to correct it. Unknown information must remain marked unknown rather than being guessed.
