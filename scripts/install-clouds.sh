#!/usr/bin/env bash
# install-clouds.sh — AWS, Azure and Google Cloud CLIs, verified (never `curl|sh`):
#   * AWS CLI v2  — pinned version + per-arch SHA256 (the official installer zip)
#   * Azure CLI   — Microsoft apt repo, GPG-signed (dist pinned; see ISK_AZ_APT_DIST)
#   * gcloud      — Google Cloud apt repo, GPG-signed (codename-independent `cloud-sdk`)
#
# Per-component and non-fatal: each CLI installs independently and a failure only
# WARNS, so a flaky vendor repo never blocks sandbox creation. Completion is tracked
# by the tool being present at the RIGHT version (AWS is checked against the pinned
# version, not just "an aws exists"), and anything missing/stale is retried by the
# kit's setup.startup step. Safe to run repeatedly; it converges. Set
# ISK_INSTALL_CLOUDS=0 to skip clouds.
#
# NOTE on error handling: each install runs in a plain subshell `( install_x ) || warn`.
# `set -e` is deliberately NOT relied on inside — Bash ignores errexit for a command on
# the left of `||`, so every fallible operation is checked explicitly with `|| return 1`
# (and lib.sh's fetch/verify_sha256 abort the subshell via die). The subshell only
# contains a die so one component's failure can't take down the others.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

AWSCLI_VERSION="${ISK_AWSCLI_VERSION:-2.36.10}"
AZ_APT_DIST="${ISK_AZ_APT_DIST:-noble}"   # Microsoft azure-cli repo has no 'resolute' (26.04) dist yet; noble works
DEB_ARCH="$(deb_arch)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# aws_is_current — true only when aws is present AND at the pinned version.
aws_is_current() { have aws && aws --version 2>&1 | grep -q "aws-cli/${AWSCLI_VERSION}"; }

# install_apt_keyring <url> <dest> — fetch a repo signing key and write a binary
# keyring to <dest>, coping with both armored (.asc) and already-binary keys.
install_apt_keyring() {
  local url="$1" dest="$2" raw="$tmp/key.raw" out="$tmp/key.gpg"
  fetch "$url" "$raw"                       # die on failure -> aborts the subshell
  if gpg --dearmor < "$raw" > "$out" 2>/dev/null; then :; else cp "$raw" "$out" || return 1; fi
  as_root install -m 0644 -D "$out" "$dest" || return 1
}

# apt_update_one <list-file-basename> — refresh ONLY the given source list (so we
# never depend on every other apt source in the base image being reachable).
apt_update_one() {
  as_root apt-get update \
    -o Dir::Etc::sourcelist="sources.list.d/$1" \
    -o Dir::Etc::sourceparts="-" \
    -o APT::Get::List-Cleanup="0"
}

# --- AWS CLI v2 (pinned, SHA256-verified, version-checked) -----------------
awscli_sha_x86_64="f6bf7f19f584a1b32b50217f357f2a5877204cf6f703fec8036cd774932383dd"
awscli_sha_aarch64="8435364a5a09004a644340131c720e081823023f9c69d5fd15f9bc650fb662fc"
install_aws() {
  if aws_is_current; then log "aws-cli ${AWSCLI_VERSION} already installed — skipping"; return 0; fi
  local a; a="$(aws_arch)"                  # x86_64 | aarch64 (dies on unknown arch)
  log "installing aws-cli v2 ${AWSCLI_VERSION} (${a})"
  fetch "https://awscli.amazonaws.com/awscli-exe-linux-${a}-${AWSCLI_VERSION}.zip" "$tmp/awscli.zip"
  case "$a" in
    x86_64)  verify_sha256 "$tmp/awscli.zip" "$awscli_sha_x86_64" ;;
    aarch64) verify_sha256 "$tmp/awscli.zip" "$awscli_sha_aarch64" ;;
    *)       warn "no pinned aws-cli checksum for arch '${a}' — refusing an unverified install"; return 1 ;;
  esac
  unzip -o -q "$tmp/awscli.zip" -d "$tmp"        || return 1
  as_root "$tmp/aws/install" --update            || return 1
  aws_is_current || { warn "aws-cli is not at ${AWSCLI_VERSION} after install"; return 1; }
  log "aws-cli installed: $(aws --version 2>&1)"
}

# --- Azure CLI (Microsoft apt repo, GPG-signed) ----------------------------
install_azure() {
  if have az; then log "azure-cli already installed — skipping"; return 0; fi
  log "installing azure-cli (Microsoft apt repo, dist ${AZ_APT_DIST})"
  install_apt_keyring "https://packages.microsoft.com/keys/microsoft.asc" /etc/apt/keyrings/microsoft.gpg || return 1
  echo "deb [arch=${DEB_ARCH} signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ ${AZ_APT_DIST} main" \
    | as_root tee /etc/apt/sources.list.d/azure-cli.list >/dev/null || return 1
  apt_update_one azure-cli.list                  || return 1
  as_root apt-get install -y azure-cli           || return 1
  have az || return 1
  log "azure-cli installed: $(az version --output tsv 2>/dev/null | head -1 || echo '?')"
}

# --- gcloud (Google Cloud apt repo, GPG-signed) ----------------------------
install_gcloud() {
  if have gcloud; then log "gcloud already installed — skipping"; return 0; fi
  log "installing google-cloud-cli (Google apt repo, dist cloud-sdk)"
  install_apt_keyring "https://packages.cloud.google.com/apt/doc/apt-key.gpg" /etc/apt/keyrings/google-cloud.gpg || return 1
  echo "deb [arch=${DEB_ARCH} signed-by=/etc/apt/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | as_root tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null || return 1
  apt_update_one google-cloud-sdk.list           || return 1
  as_root apt-get install -y google-cloud-cli    || return 1
  have gcloud || return 1
  log "gcloud installed: $(gcloud version 2>/dev/null | head -1 || echo '?')"
}

# Install each independently. A failure warns and moves on; the startup step retries
# whatever is still missing or stale. The subshell contains die() so one failure can't
# abort the others.
( install_aws )    || warn "aws-cli install failed (will retry on next start)"
( install_azure )  || warn "azure-cli install failed (will retry on next start)"
( install_gcloud ) || warn "gcloud install failed (will retry on next start)"

missing=""
aws_is_current || missing="$missing aws"
have az        || missing="$missing az"
have gcloud    || missing="$missing gcloud"
if [ -n "$missing" ]; then
  warn "cloud CLIs missing or stale:${missing} — the kit's startup step will retry them"
else
  log "all cloud CLIs present and current"
fi
exit 0
