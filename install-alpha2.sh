#!/usr/bin/env bash
# Installer for Symbia Alpha-2 demo harness (early access mirror).
# Downloads a release tarball from this repo, verifies checksum, and installs shims.
set -euo pipefail

REPO="${REPO:-Symbia-Labs/symbia-alpha2-early-access}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.symbia-seed-dist}"
BIN_DIR="${BIN_DIR:-$HOME/bin}"
VERSION="${VERSION:-}"
FORCE=1

usage() {
  cat <<'EOF_HELP'
Install Symbia Alpha-2 (no git clone required)

Usage: install-alpha2.sh [--version <tag>] [--install-dir <path>] [--bin-dir <path>] [--repo <owner/name>] [--force]

Flags:
  --version       Release tag to install (defaults to latest GitHub release)
  --install-dir   Destination directory (default: ~/.symbia-seed-dist)
  --bin-dir       Where to place shims (default: ~/bin)
  --repo          GitHub repo (default: Symbia-Labs/symbia-alpha2-early-access)
  --force         Remove existing install dir before unpacking
  -h, --help      Show this help

After install:
  symbia boot dev      # start dev instance
  alpha-2 missionctl   # run demo harness
EOF_HELP
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) VERSION="$2"; shift 2 ;;
      --install-dir) INSTALL_DIR="$2"; shift 2 ;;
      --bin-dir) BIN_DIR="$2"; shift 2 ;;
      --repo) REPO="$2"; shift 2 ;;
      --force) FORCE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
  done
}

latest_release() {
  local tag
  tag="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | sed -n 's/.*\"tag_name\": *\"\([^\"]*\)\".*/\1/p' | head -n1)"
  if [[ -z "$tag" ]]; then
    echo "Failed to discover latest release tag from GitHub API." >&2
    exit 1
  fi
  echo "$tag"
}

fetch() {
  local url="$1" dest="$2"
  if ! curl -fL "$url" -o "$dest"; then
    return 1
  fi
}

verify_checksum() {
  local archive="$1" checksum_file="$2"
  if [[ ! -f "$checksum_file" ]]; then
    echo "Checksum file missing; skipping verification." >&2
    return 0
  fi
  local tool
  if command -v sha256sum >/dev/null 2>&1; then
    tool="sha256sum"
  else
    tool="shasum -a 256"
  fi
  if ! (cd "$(dirname "$checksum_file")" && $tool -c "$(basename "$checksum_file")"); then
    echo "Checksum verification failed." >&2
    exit 1
  fi
}

install_files() {
  local archive="$1"
  [[ "$FORCE" -eq 1 ]] && rm -rf "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  tar -xzf "$archive" -C "$INSTALL_DIR" --strip-components 1
}

link_shims() {
  mkdir -p "$BIN_DIR"
  ln -sf "$INSTALL_DIR/scripts/seed.sh" "$BIN_DIR/symbia"
  ln -sf "$INSTALL_DIR/scripts/alpha-2.sh" "$BIN_DIR/alpha-2"
}

main() {
  parse_args "$@"
  need_cmd curl
  need_cmd tar

  if [[ -z "$VERSION" ]]; then
    VERSION="$(latest_release)"
  fi
  local base="symbia-seed-alpha2-${VERSION}"
  local url_base="https://github.com/${REPO}/releases/download/${VERSION}"
  local tmp
  tmp="$(mktemp -d)"
  local archive="$tmp/${base}.tar.gz"
  local checksum="$tmp/${base}.sha256"

  echo "Downloading ${base} ..."
  if ! fetch "${url_base}/${base}.tar.gz" "$archive"; then
    echo "Failed to download ${url_base}/${base}.tar.gz" >&2
    exit 1
  fi

  if fetch "${url_base}/${base}.sha256" "$checksum"; then
    verify_checksum "$archive" "$checksum"
  else
    echo "Checksum not found; proceeding without verification." >&2
  fi

  install_files "$archive"
  link_shims

  echo ""
  echo "Installed to: $INSTALL_DIR"
  echo "Shims:        $BIN_DIR/symbia, $BIN_DIR/alpha-2"
  echo "Next steps:"
  echo "  export PATH=\"$BIN_DIR:\$PATH\""
  echo "  symbia boot dev"
  echo "  alpha-2 missionctl"
}

main "$@"
