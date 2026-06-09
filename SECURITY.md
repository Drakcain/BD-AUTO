# Security

## Reporting

Report suspected security issues privately through GitHub's security advisory feature. Do not publish credentials, tokens, or sensitive logs in a public issue.

## Download Safety

Use only release assets attached to this repository. Published releases include a SHA-256 digest.

BD-AUTO downloads:

- BetterDiscord CLI from `github.com/BetterDiscord/cli`
- plugins and themes from the HTTPS URLs pinned in `payload/addons.manifest.json`

The BetterDiscord CLI archive is checked against the upstream release's published SHA-256 checksum before extraction.

## Scope

BD-AUTO does not collect telemetry, Discord tokens, messages, or credentials. It does not delete Discord user data.
