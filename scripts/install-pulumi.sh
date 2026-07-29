#!/usr/bin/env bash
# install-pulumi.sh — install a pinned, checksum-verified Pulumi CLI (with all the
# bundled language/resource plugins) system-wide. ESC is reached via `pulumi env`;
# the standalone `esc` CLI was retired by Pulumi in 2026, so it is not installed.
#
# Idempotent: skips when the pinned version is already installed. Downloads come
# from GitHub release assets (get.pulumi.com just redirects there) so the same
# URLs work inside a locked-down sandbox as long as github.com and
# objects.githubusercontent.com are on the network allow-list.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

PULUMI_VERSION="${ISK_PULUMI_VERSION:-3.255.0}"
PREFIX="/opt/pulumi"
ARCH="$(rel_arch)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- Pulumi CLI ------------------------------------------------------------
# Per-arch checksums, pinned to PULUMI_VERSION. Source of truth:
#   https://get.pulumi.com/releases/sdk/pulumi-<version>-checksums.txt
# Bump both when you change PULUMI_VERSION.
pulumi_sha_x64="cf559568e2c32f7fae56ea3de8ae5fa48973ba8c5aa9dd2b3dc0c8898fe50dba"
pulumi_sha_arm64="699fbc6ea848d997e9b3645487f108d27b1b55ec807c7576406131e6e080f0e3"

current_pulumi=""
have pulumi && current_pulumi="$(pulumi version 2>/dev/null | sed 's/^v//')"
if [ "$current_pulumi" = "$PULUMI_VERSION" ]; then
  log "pulumi ${PULUMI_VERSION} already installed — skipping"
else
  log "installing pulumi ${PULUMI_VERSION} (${ARCH})"
  tarball="pulumi-v${PULUMI_VERSION}-linux-${ARCH}.tar.gz"
  fetch "https://github.com/pulumi/pulumi/releases/download/v${PULUMI_VERSION}/${tarball}" "$tmp/$tarball"
  case "$ARCH" in
    x64)   verify_sha256 "$tmp/$tarball" "$pulumi_sha_x64" ;;
    arm64) verify_sha256 "$tmp/$tarball" "$pulumi_sha_arm64" ;;
  esac
  tar -C "$tmp" -xzf "$tmp/$tarball"          # extracts to $tmp/pulumi/
  as_root rm -rf "$PREFIX"
  as_root mkdir -p "$PREFIX"
  as_root cp -a "$tmp"/pulumi/. "$PREFIX"/
  # Every binary is named pulumi*; symlink them all into /usr/local/bin so they
  # resolve in non-login shells too (Pulumi finds its language/resource plugins
  # by PATH lookup of the pulumi-* siblings).
  as_root sh -c 'for f in "'"$PREFIX"'"/pulumi*; do ln -sf "$f" "/usr/local/bin/$(basename "$f")"; done'
  have pulumi || die "pulumi not on PATH after install"
  log "pulumi installed: $(pulumi version)"
fi
