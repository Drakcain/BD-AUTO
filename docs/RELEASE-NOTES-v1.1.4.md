# BD-AUTO v1.1.4 Release Notes

## Installer And Update Flow

- Adds a local updater shortcut for installed BD-AUTO users.
- Hardens update/install flow so release retrieval stays focused on the installer artifact.
- Keeps `BD-AUTO-Setup.exe` as the primary end-user download.

## Runtime

- Preserves the installer-first BetterDiscord repair workflow.
- Preserves downgrade-safe add-on synchronization behavior.
- Preserves installed-newer add-on protection.
- Preserves bundled-first BetterDiscord CLI behavior with checksum verification and fallback handling.
- Preserves Discord-only scope and does not add update-all behavior.

## GitHub Release Presentation

- Public releases may include `BD-AUTO-Setup.exe.sha256` as an optional verification file.
- Normal users should download `BD-AUTO-Setup.exe`.
- The checksum file is for manual verification only and is not the installer.

## Validation

- Repository validation passed.
- Installer build passed.
- Release packaging continued to produce `BD-AUTO-Setup.exe` plus the optional checksum file.
