#!/usr/bin/env bash
# provision.sh — orchestrate the full pulumi-sandbox-kit provisioning:
#   1. Pulumi CLI + ESC          (install-pulumi.sh)
#   2. language toolchains/LSPs  (install-toolchains.sh)
#   3. APM + my-claude-apm-setup (setup-apm-home.sh)
#
# Used by BOTH entry points:
#   * template Dockerfile — scripts COPYed in, run once at build time.
#   * zero-build mixin    — scripts fetched at sandbox-create time, run once.
#
# A sentinel makes a re-run a fast no-op (e.g. when the mixin is layered on a
# template that already baked everything). Force a re-run with PSK_FORCE=1.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

SENTINEL="$HOME/.local/state/pulumi-sandbox-kit/provisioned"

if [ -f "$SENTINEL" ] && [ "${PSK_FORCE:-0}" != "1" ]; then
  log "already provisioned ($SENTINEL) — skipping (set PSK_FORCE=1 to re-run)"
  exit 0
fi

log "provisioning: pulumi=${PSK_PULUMI_VERSION:-3.255.0} esc=${PSK_ESC_VERSION:-0.26.0} apm-setup=${PSK_APM_SETUP_REF:-v0.4.0} dotnet=${PSK_INSTALL_DOTNET:-0}"

bash "$SCRIPT_DIR/install-pulumi.sh"
bash "$SCRIPT_DIR/install-toolchains.sh"
bash "$SCRIPT_DIR/setup-apm-home.sh"

mkdir -p "$(dirname "$SENTINEL")"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$SENTINEL" 2>/dev/null || : > "$SENTINEL"
log "provisioning complete"
