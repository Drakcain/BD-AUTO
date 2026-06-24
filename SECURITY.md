# Security

Current release:

```text
v1.1.4
```

## Reporting

Report suspected security issues privately through GitHub's security advisory feature. Do not publish credentials, tokens, or sensitive logs in a public issue.

## Credentials

BD-AUTO does not require:

- Discord credentials
- Discord tokens
- BetterDiscord credentials
- API keys
- tokens

Never enter Discord credentials into BD-AUTO.

## Download Safety

Use only release assets attached to this repository. Published releases include a SHA-256 digest.

BD-AUTO downloads:

- BetterDiscord CLI from `github.com/BetterDiscord/cli`
- plugins and themes from the HTTPS URLs pinned in `payload/addons.manifest.json`

The BetterDiscord CLI archive is checked against the upstream release's published SHA-256 checksum before extraction.

Add-on files are validated against their declared name and version metadata. This is an integrity and drift check, not a security audit or endorsement of third-party code. Review upstream source before enabling an add-on.

## Scope

BD-AUTO does not collect telemetry, Discord tokens, messages, or credentials. It does not delete Discord user data.

## Local Data

Runtime files under `C:\Tools\BD-AUTO\runtime\` and `C:\Tools\BD-AUTO\logs\` can reveal local Discord paths, add-on state, target-profile resolution, compatibility results, and repair history.

Review logs and runtime JSON files before sharing them publicly.

See `THIRD-PARTY-NOTICES.md` for ownership, license, and no-affiliation disclosures.
