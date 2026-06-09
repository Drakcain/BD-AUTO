# Installed Runtime

This directory is installed to `C:\Tools\BD-AUTO` by BD-AUTO Setup.

Use the **Repair BetterDiscord** desktop or Start Menu shortcut for a manual repair. Source, build instructions, and release downloads are maintained at:

https://github.com/Drakcain/BD-AUTO

The project license and third-party notices are installed beside this file. Review `THIRD-PARTY-NOTICES.md` before redistributing a populated add-on cache.

Resolved per-user paths are recorded in `runtime\target-profile.json`. Add-ons must be installed under the same Windows profile that runs Discord.

Release builds include a checksum-verified official BetterDiscord CLI under `bin`. winget is not required.

Compatibility and setup results are recorded in:

- `runtime\compatibility.json`
- `runtime\install-summary.txt`
- `runtime\task-status.json`

Task Scheduler is optional. If scheduled automation is unavailable on a customized Windows build, the manual repair shortcuts remain supported.
