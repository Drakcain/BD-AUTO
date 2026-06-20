# Project Identity

Product name:

```text
BD-AUTO
```

Active local repository path:

```text
D:\GITHUB BUILDS\WINDOWS\BD-AUTO
```

Active GitHub repository:

```text
https://github.com/Drakcain/BD-AUTO
```

Installer target:

```text
C:\Tools\BD-AUTO
```

Primary release artifact:

```text
BD-AUTO-Setup.exe
```

## Product Position

BD-AUTO is a Windows BetterDiscord repair and add-on synchronization utility.

It is installer-first, repair-focused, and deliberately scoped to Discord Stable and BetterDiscord maintenance.

## Safety Boundaries

- No Discord token collection
- No telemetry collection
- No forced Discord uninstall/reinstall
- No system-wide updater behavior
- No random third-party addon scraping outside the pinned manifest sources

## Current Code Shape

- `payload\` contains the installed repair and watchdog logic.
- `installer\` contains the Inno Setup installer definition.
- `scripts\` contains build, validation, and compatibility checks.
- `docs\` contains release and operator documentation.

