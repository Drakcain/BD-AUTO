# BD-AUTO v1.1.2 Release Notes

## Branding

- Adds the approved BD-AUTO dark repair-dashboard visual identity to the project surface.
- Adds a project-owned BD-AUTO banner for README and release presentation.
- Adds branded installer sidebar, header, and setup icon assets generated from repository-owned source art.

## Installer

- Keeps the `v1.1.1` installer finalization behavior.
- Retains the explicit warning that hidden repair and relaunch work can continue for up to 2 minutes.
- Keeps Cancel disabled during hidden finalization.
- Keeps no-desktop-shortcut behavior and the Start Menu repair path unchanged.

## Workflow

- Hardens GitHub Actions release publishing so a build no longer fails only because a release for the tag already exists.
- Preserves existing public releases instead of mutating them implicitly.

## Runtime

- No runtime repair logic changes.
- No addon synchronization policy changes.
- No watchdog trigger behavior changes.
- No Discord close/relaunch behavior changes.

## Validation

- Repository validation passed.
- Installer build passed.
- Silent install and local reinstall validation remained healthy.
- Discord relaunch, injection verification, addon audit health, and shortcut behavior remained unchanged.
