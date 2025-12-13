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
