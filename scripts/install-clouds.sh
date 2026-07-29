#!/usr/bin/env bash
# install-clouds.sh — AWS, Azure and Google Cloud CLIs, verified (never `curl|sh`):
#   * AWS CLI v2  — pinned version + per-arch SHA256 (the official installer zip)
#   * Azure CLI   — Microsoft apt repo, GPG-signed (dist pinned; see ISK_AZ_APT_DIST)
#   * gcloud      — Google Cloud apt repo, GPG-signed (codename-independent `cloud-sdk`)
#
# AWS is fatal on failure (rock-solid pinned download); the apt-based Azure/gcloud
# installs are best-effort (warn, don't abort) so a flaky vendor repo never blocks
# the rest of provisioning (APM, etc.). All idempotent.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

AWSCLI_VERSION="${ISK_AWSCLI_VERSION:-2.36.10}"
AZ_APT_DIST="${ISK_AZ_APT_DIST:-noble}"   # Microsoft azure-cli repo has no 'resolute' (26.04) dist yet; noble works
DEB_ARCH="$(deb_arch)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# install_apt_keyring <url> <dest> — fetch a repo signing key and write a binary
# keyring to <dest>, coping with both armored (.asc) and already-binary keys.
install_apt_keyring() {
  local url="$1" dest="$2" raw="$tmp/key.raw" out="$tmp/key.gpg"
  fetch "$url" "$raw"
  if gpg --dearmor < "$raw" > "$out" 2>/dev/null; then :; else cp "$raw" "$out"; fi
  as_root install -m 0644 -D "$out" "$dest"
}

# apt_update_one <list-file-basename> — refresh ONLY the given source list (so we
# never depend on every other apt source in the base image being reachable).
apt_update_one() {
  as_root apt-get update \
    -o Dir::Etc::sourcelist="sources.list.d/$1" \
    -o Dir::Etc::sourceparts="-" \
    -o APT::Get::List-Cleanup="0"
}

# --- AWS CLI v2 (pinned, SHA256-verified) — fatal --------------------------
awscli_sha_x86_64="f6bf7f19f584a1b32b50217f357f2a5877204cf6f703fec8036cd774932383dd"
awscli_sha_aarch64="8435364a5a09004a644340131c720e081823023f9c69d5fd15f9bc650fb662fc"
if have aws && aws --version 2>&1 | grep -q "aws-cli/${AWSCLI_VERSION}"; then
  log "aws-cli ${AWSCLI_VERSION} already installed — skipping"
else
  a="$(aws_arch)"                        # x86_64 | aarch64
  log "installing aws-cli v2 ${AWSCLI_VERSION} (${a})"
  fetch "https://awscli.amazonaws.com/awscli-exe-linux-${a}-${AWSCLI_VERSION}.zip" "$tmp/awscli.zip"
  case "$a" in
    x86_64)  verify_sha256 "$tmp/awscli.zip" "$awscli_sha_x86_64" ;;
    aarch64) verify_sha256 "$tmp/awscli.zip" "$awscli_sha_aarch64" ;;
  esac
  unzip -o -q "$tmp/awscli.zip" -d "$tmp"
  as_root "$tmp/aws/install" --update
  have aws || die "aws not on PATH after install"
  log "aws-cli installed: $(aws --version 2>&1)"
fi

# --- Azure CLI (Microsoft apt repo, GPG-signed) — best-effort --------------
install_azure() {
  if have az; then log "azure-cli already installed — skipping"; return 0; fi
  log "installing azure-cli (Microsoft apt repo, dist ${AZ_APT_DIST})"
  install_apt_keyring "https://packages.microsoft.com/keys/microsoft.asc" /etc/apt/keyrings/microsoft.gpg
  echo "deb [arch=${DEB_ARCH} signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ ${AZ_APT_DIST} main" \
    | as_root tee /etc/apt/sources.list.d/azure-cli.list >/dev/null
  apt_update_one azure-cli.list
  as_root apt-get install -y azure-cli
  have az || return 1
  log "azure-cli installed: $(az version --output tsv 2>/dev/null | head -1 || echo '?')"
}

# --- gcloud (Google Cloud apt repo, GPG-signed) — best-effort --------------
install_gcloud() {
  if have gcloud; then log "gcloud already installed — skipping"; return 0; fi
  log "installing google-cloud-cli (Google apt repo, dist cloud-sdk)"
  install_apt_keyring "https://packages.cloud.google.com/apt/doc/apt-key.gpg" /etc/apt/keyrings/google-cloud.gpg
  echo "deb [arch=${DEB_ARCH} signed-by=/etc/apt/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | as_root tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
  apt_update_one google-cloud-sdk.list
  as_root apt-get install -y google-cloud-cli
  have gcloud || return 1
  log "gcloud installed: $(gcloud version 2>/dev/null | head -1 || echo '?')"
}

( set -e; install_azure ) || warn "azure-cli install failed (non-fatal) — install later with: sudo apt-get install azure-cli"
( set -e; install_gcloud ) || warn "gcloud install failed (non-fatal) — install later with: sudo apt-get install google-cloud-cli"
