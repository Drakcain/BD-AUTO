# Installer Signing

BD-AUTO release installers are unsigned unless a release explicitly states otherwise.

## What Signing Changes

- A trusted Authenticode signature identifies the publisher and helps Windows establish SmartScreen reputation.
- An EV code-signing certificate may establish reputation faster than a standard certificate.
- A standard code-signing certificate still improves publisher verification, but reputation can take time.

## What Signing Does Not Change

- Signing does not remove the Windows User Account Control prompt.
- BD-AUTO installs machine-wide files and optional scheduled automation, so Windows still requires administrator approval.
- BD-AUTO does not bypass UAC, SmartScreen, Defender, or other Windows security controls.

Expected installation flow:

```text
Double-click installer -> review SmartScreen if shown -> approve UAC -> setup completes
```

## Release Security

- Never commit certificate files, private keys, passwords, hardware-token credentials, or signing service tokens.
- GitHub Actions signing must use protected repository or environment secrets.
- Release notes should state whether the installer is signed and publish its SHA-256 checksum.
- Do not add automated signing until a legitimate certificate and protected secret workflow are available.
