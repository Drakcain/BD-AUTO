# BD-AUTO v1.1.0 Release Notes

## Repair

- Uses the bundled official BetterDiscord CLI before considering PATH, winget links, or a network download.
- Downloads a CLI only when no usable local copy exists and verifies the official SHA-256 checksum.
- Repairs when the Discord app directory path or write time changes after a Discord update.
- Verifies the actual `BetterDiscord\data\betterdiscord.asar` injection path.
- Records the repair method and CLI path in runtime state.
- Allows the hidden task to repair per-user Discord files without unnecessary elevation and falls back to UAC only after a real CLI failure.

## Addons

- Replaces exact manifest-version enforcement with installed/upstream/cache version comparison.
- Preserves a newer installed addon instead of restoring an older cached or upstream copy.
- Updates from upstream only when the upstream version is newer.
- Uses the cache only as a fallback when upstream is unavailable or the active file is missing.
- Preserves the installed file when versions cannot be compared safely.
- Backs up installed addons before replacement.
- Updates the BDFDB audit baseline from 4.5.3 to 4.5.4.
- Adds source repository identities and downgrade-safe policies to every manifest entry.
- Keeps CallTimeCounter as an explicit `KingGamingYT/CallTimeCounter` exception source with Rasync and BetterDiscord Team attribution.
- Adds `-AddonAudit` and `-PluginAudit` for read-only version/source reporting.

## Installer

- Adds `Install-BD-AUTO.cmd` for a double-click portable source bootstrap.
- Keeps `BD-AUTO-Setup.exe` as the preferred friend-facing installer.
- Writes addon decisions to `C:\Tools\BD-AUTO\runtime\addon-audit.json`.
- Retains hidden sign-in and resume triggers without a recurring background timer.
- Reports stock UAC prompting, administrator auto-elevation policies, and disabled-UAC systems without changing Windows security policy.

## Validation

- Adds regression tests for the BDFDB downgrade loop.
- Tests upstream upgrades, cache fallback, unknown-version safety, and replacement backups.

## Release State

This document describes the v1.1.0 candidate. It is not public until the source is committed, tagged, pushed, and the GitHub release artifact is published.
