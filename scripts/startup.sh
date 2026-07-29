#!/usr/bin/env bash
# startup.sh — the kit's commands.startup entrypoint; runs on every sandbox start.
#   1. Re-apply the APM guardrail hooks + MCP servers (Docker reseeds Claude's agent
#      config at create time, so this keeps them present).
#   2. Retry any cloud CLI that isn't installed yet. Cloud installs are per-component
#      and non-fatal at provision time, so a flaky vendor repo never blocks sandbox
#      creation — the missing tool is filled in here and converges over restarts.
# Both steps are idempotent and non-fatal, so a start never fails because of them.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tag="[infrastructure-sandbox-kit]"
log() { printf '%s %s\n' "$tag" "$*" >&2; }
STATE_DIR="$HOME/.local/state/infrastructure-sandbox-kit"

# 1. Agent config (guardrail hooks + MCP servers) --------------------------
if [ -f "$SCRIPT_DIR/apply-agent-config.sh" ]; then
  bash "$SCRIPT_DIR/apply-agent-config.sh" || log "apply-agent-config failed (non-fatal)"
fi

# 2. Fill in any missing/stale cloud CLI, only if they were requested at provision
#    time. install-clouds.sh is per-component and version-aware, so it re-installs a
#    stale AWS CLI and a missing az/gcloud while skipping what's already current. It
#    is a fast no-op once everything is present at the right version.
if [ -f "$STATE_DIR/clouds-requested" ] && [ -f "$SCRIPT_DIR/install-clouds.sh" ]; then
  bash "$SCRIPT_DIR/install-clouds.sh" || log "cloud CLIs still incomplete; will retry next start"
fi
