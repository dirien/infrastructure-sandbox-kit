#!/usr/bin/env bash
# install-iac.sh — Terraform + OpenTofu CLIs, pinned and verified against each
# vendor's published SHA256SUMS (no `curl | sh`). System-wide, idempotent.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

TERRAFORM_VERSION="${ISK_TERRAFORM_VERSION:-1.15.8}"
OPENTOFU_VERSION="${ISK_OPENTOFU_VERSION:-1.12.5}"
ARCH="$(deb_arch)"                       # amd64 | arm64

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- Terraform (HashiCorp releases, SHA256SUMS-verified) -------------------
current_tf=""
have terraform && current_tf="$(terraform version 2>/dev/null | head -1 | awk '{print $2}' | sed 's/^v//')"
if [ "$current_tf" = "$TERRAFORM_VERSION" ]; then
  log "terraform ${TERRAFORM_VERSION} already installed — skipping"
else
  log "installing terraform ${TERRAFORM_VERSION} (${ARCH})"
  zip="terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip"
  base="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}"
  fetch "${base}/${zip}" "$tmp/$zip"
  fetch "${base}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" "$tmp/tf-sums"
  verify_from_sums "$tmp/$zip" "$zip" "$tmp/tf-sums"
  unzip -o -q "$tmp/$zip" -d "$tmp/tf"
  as_root install -m 0755 "$tmp/tf/terraform" /usr/local/bin/terraform
  have terraform || die "terraform not on PATH after install"
  log "terraform installed: $(terraform version | head -1)"
fi

# --- OpenTofu (GitHub releases, SHA256SUMS-verified) -----------------------
current_tofu=""
have tofu && current_tofu="$(tofu version 2>/dev/null | head -1 | awk '{print $2}' | sed 's/^v//')"
if [ "$current_tofu" = "$OPENTOFU_VERSION" ]; then
  log "opentofu ${OPENTOFU_VERSION} already installed — skipping"
else
  log "installing opentofu ${OPENTOFU_VERSION} (${ARCH})"
  zip="tofu_${OPENTOFU_VERSION}_linux_${ARCH}.zip"
  base="https://github.com/opentofu/opentofu/releases/download/v${OPENTOFU_VERSION}"
  fetch "${base}/${zip}" "$tmp/$zip"
  fetch "${base}/tofu_${OPENTOFU_VERSION}_SHA256SUMS" "$tmp/tofu-sums"
  verify_from_sums "$tmp/$zip" "$zip" "$tmp/tofu-sums"
  unzip -o -q "$tmp/$zip" -d "$tmp/tofu"
  as_root install -m 0755 "$tmp/tofu/tofu" /usr/local/bin/tofu
  have tofu || die "tofu not on PATH after install"
  log "opentofu installed: $(tofu version | head -1)"
fi
