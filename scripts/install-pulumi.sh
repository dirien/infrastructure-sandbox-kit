#!/usr/bin/env bash
# install-pulumi.sh — install a pinned, checksum-verified Pulumi CLI (with all
# the bundled language/resource plugins) and the Pulumi ESC CLI, system-wide.
#
# Idempotent: skips when the pinned version is already installed. Downloads come
# from GitHub release assets (get.pulumi.com just redirects there) so the same
# URLs work inside a locked-down sandbox as long as github.com and
# objects.githubusercontent.com are on the network allow-list.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

PULUMI_VERSION="${PSK_PULUMI_VERSION:-3.255.0}"
ESC_VERSION="${PSK_ESC_VERSION:-0.26.0}"
PREFIX="/opt/pulumi"
ARCH="$(psk_arch)"

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

# --- Pulumi ESC CLI --------------------------------------------------------
current_esc=""
have esc && current_esc="$(esc version 2>/dev/null | sed 's/^v//')"
if [ "$current_esc" = "$ESC_VERSION" ]; then
  log "esc ${ESC_VERSION} already installed — skipping"
else
  log "installing esc ${ESC_VERSION} (${ARCH})"
  esc_tarball="esc-v${ESC_VERSION}-linux-${ARCH}.tar.gz"
  fetch "https://github.com/pulumi/esc/releases/download/v${ESC_VERSION}/${esc_tarball}" "$tmp/$esc_tarball"
  # Verify against the release's published checksums when available (best-effort).
  if fetch "https://github.com/pulumi/esc/releases/download/v${ESC_VERSION}/esc-${ESC_VERSION}-checksums.txt" "$tmp/esc-sums.txt" 2>/dev/null; then
    expected="$(grep "linux-${ARCH}.tar.gz" "$tmp/esc-sums.txt" | awk '{print $1}' | head -1)"
    if [ -n "$expected" ]; then verify_sha256 "$tmp/$esc_tarball" "$expected"; else warn "esc checksum entry not found; skipping verification"; fi
  else
    warn "esc checksums unavailable; skipping verification"
  fi
  tar -C "$tmp" -xzf "$tmp/$esc_tarball"
  esc_bin="$(find "$tmp" -type f -name esc | head -1)"
  [ -n "$esc_bin" ] || die "esc binary not found in archive"
  as_root install -m 0755 "$esc_bin" /usr/local/bin/esc
  log "esc installed: $(esc version 2>/dev/null || echo '?')"
fi
