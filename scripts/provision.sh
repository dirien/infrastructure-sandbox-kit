#!/usr/bin/env bash
# provision.sh — orchestrate the full infrastructure-sandbox-kit provisioning:
#   1. Pulumi CLI + ESC              (install-pulumi.sh)
#   2. Terraform + OpenTofu          (install-iac.sh)
#   3. AWS / Azure / gcloud CLIs     (install-clouds.sh; ISK_INSTALL_CLOUDS=1, default on)
#   4. language toolchains / LSPs    (install-toolchains.sh)
#   5. APM + my-claude-apm-setup     (setup-apm-home.sh)
#
# Used by BOTH entry points:
#   * template Dockerfile — scripts COPYed in, run once at build time.
#   * zero-build mixin    — scripts fetched at sandbox-create time, run once.
#
# A sentinel makes a re-run a fast no-op (e.g. when the mixin is layered on a
# template that already baked everything). Force a re-run with ISK_FORCE=1.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

SENTINEL="$HOME/.local/state/infrastructure-sandbox-kit/provisioned"

if [ -f "$SENTINEL" ] && [ "${ISK_FORCE:-0}" != "1" ]; then
  log "already provisioned ($SENTINEL) — skipping (set ISK_FORCE=1 to re-run)"
  exit 0
fi

log "provisioning: pulumi=${ISK_PULUMI_VERSION:-3.255.0} terraform=${ISK_TERRAFORM_VERSION:-1.15.8} opentofu=${ISK_OPENTOFU_VERSION:-1.12.5} clouds=${ISK_INSTALL_CLOUDS:-1} dotnet=${ISK_INSTALL_DOTNET:-0}"

bash "$SCRIPT_DIR/install-pulumi.sh"
bash "$SCRIPT_DIR/install-iac.sh"
if [ "${ISK_INSTALL_CLOUDS:-1}" = "1" ]; then
  bash "$SCRIPT_DIR/install-clouds.sh"
else
  log "ISK_INSTALL_CLOUDS=0 — skipping AWS/Azure/gcloud CLIs"
fi
bash "$SCRIPT_DIR/install-toolchains.sh"
bash "$SCRIPT_DIR/setup-apm-home.sh"

mkdir -p "$(dirname "$SENTINEL")"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$SENTINEL" 2>/dev/null || : > "$SENTINEL"
log "provisioning complete"
