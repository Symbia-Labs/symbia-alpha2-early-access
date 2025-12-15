# Symbia Alpha-2 Early Access

Early-access distribution for the Symbia Alpha-2 demo harness (missionctl) without cloning the main repo.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Symbia-Labs/symbia-alpha2-early-access/main/install-alpha2.sh | bash
```

By default this:
- Downloads the latest Alpha-2 release tarball from this repo
- Installs to `~/.symbia-seed-dist`
- Installs shims to `~/bin` (`symbia`, `alpha-2`)

Then run:

```bash
symbia boot dev
alpha-2 missionctl
```

## Manual download

If you prefer manual download, grab the latest `symbia-seed-alpha2-*.tar.gz` from Releases and unpack anywhere, then add `scripts/seed.sh` and `scripts/alpha-2.sh` to your PATH.

Notes:
- Release artifacts omit large model files to keep the download small; fetch models separately only if you need them.
- SHA256 verification is required by the installer. Cosign signatures (keyless) are attached to releases; verify with:
  - `cosign verify-blob --certificate <tar.gz>.crt --signature <tar.gz>.sig --certificate-identity-regexp "https://github.com/Symbia-Labs/symbia-seed/.*" --certificate-oidc-issuer https://token.actions.githubusercontent.com <tar.gz>`

## Release notes

- Installer now uses a single mktemp directory (macOS/Linux), logs the temp and archive paths, cleans up on exit, and verifies SHA256 against the exact downloaded archive for deterministic checks.
