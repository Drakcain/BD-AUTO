# BD-AUTO v1.1.1 Release Notes

## Installer UX

- Keeps the public `v1.1.0` release immutable and ships this installer-only polish under a new version.
- Updates the final installer screen to explain that hidden BetterDiscord repair, addon synchronization, and repair-task setup may continue for up to 2 minutes after the progress bar fills.
- Disables Cancel during the hidden post-install phase so users do not abort setup while Discord is being repaired and relaunched.
- Restores the normal completed state after background finalization finishes.

## Runtime

- No runtime behavior change from `v1.1.0`.
- BetterDiscord repair remains `bdcli`-first.
- Source-aware addon restore and downgrade protection remain unchanged.
- Desktop shortcut suppression and Start Menu repair fallback remain unchanged.

## Validation

- Revalidated reinstall behavior on the test machine.
- Confirmed Discord was relaunched after setup.
- Confirmed no desktop shortcut was created.
- Confirmed the Start Menu repair shortcut remains installed.
- Confirmed addon audit completed with 18 addons and zero problems.

## Release State

This document describes the public `v1.1.1` release. Use it instead of modifying the already-published `v1.1.0` asset or checksum.
