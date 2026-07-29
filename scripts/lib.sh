#!/usr/bin/env bash
# lib.sh — shared helpers for the pulumi-sandbox-kit provisioning scripts.
#
# Sourced by install-pulumi.sh, install-toolchains.sh, setup-apm-home.sh and
# provision.sh. Assumes it runs as the sandbox `agent` user (uid 1000) which has
# passwordless sudo — the same contract for both entry points:
#   * the template Dockerfile runs these as USER agent, and
#   * the zero-build mixin runs provision.sh with `user: "1000"`.
#
# Self-contained: bash, coreutils, curl, tar, sudo — all present in the base
# docker/sandbox-templates:claude-code(-docker) image.

set -euo pipefail

PSK_TAG="[pulumi-sandbox-kit]"

log()  { printf '%s %s\n' "$PSK_TAG" "$*" >&2; }
warn() { printf '%s WARN: %s\n' "$PSK_TAG" "$*" >&2; }
die()  { printf '%s ERROR: %s\n' "$PSK_TAG" "$*" >&2; exit 1; }

# have <cmd> — true when the command is on PATH.
have() { command -v "$1" >/dev/null 2>&1; }

# as_root <cmd...> — run with root privileges whether we are already root or an
# unprivileged user with passwordless sudo.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

# psk_arch — the release-artifact arch token used by Pulumi and ESC: x64 | arm64.
psk_arch() {
  local a
  a="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  case "$a" in
    amd64|x86_64) echo "x64" ;;
    arm64|aarch64) echo "arm64" ;;
    *) die "unsupported architecture: $a (expected amd64/x86_64 or arm64/aarch64)" ;;
  esac
}

# fetch <url> <dest> — HTTPS-only download with retries; fails on any HTTP error.
fetch() {
  curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-delay 2 -o "$2" "$1"
}

# verify_sha256 <file> <expected-hex> — abort unless the file matches.
verify_sha256() {
  local got
  got="$(sha256sum "$1" | awk '{print $1}')"
  [ "$got" = "$2" ] || die "checksum mismatch for $1: got $got, expected $2"
}

# npm_g <pkg...> — install global npm packages, falling back to sudo when the
# global prefix is not writable by the agent user.
npm_g() {
  if npm install -g "$@" >/dev/null 2>&1; then
    return 0
  fi
  as_root npm install -g "$@"
}
