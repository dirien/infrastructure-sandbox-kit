#!/usr/bin/env bash
# setup-apm-home.sh — install APM and materialize dirien/my-claude-apm-setup into
# the agent's USER-GLOBAL Claude config (~/.claude), so the skills, subagents,
# rules, guardrail hooks and MCP servers are active in every workspace opened in
# the sandbox, with no per-repo apm.yml required.
#
# What it wires:
#   ~/.claude/skills/*         <- the 23 pinned APM skills (durable across restarts)
#   ~/.claude/agents/*         <- executor / librarian / reviewer subagents (durable)
#   ~/.claude/rules/*          <- the instruction rules (durable)
#   ~/.claude/CLAUDE.md        <- a managed block importing those rules
#   ~/.claude/settings.json    <- guardrail hooks     (via apply-agent-config.sh)
#   ~/.claude.json mcpServers  <- pulumi              (via apply-agent-config.sh)
#
# The settings.json/.claude.json parts are re-applied on every sandbox start by
# the kit's setup.startup step, because Docker reseeds agent config at create
# time. This script does the one-time install and the durable file placement, then
# calls apply-agent-config.sh once so the config is present right after provisioning.
#
# Runs as the agent user. Re-runnable; safe to call again after `git pull`.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

APM_REPO="${ISK_APM_SETUP_REPO:-dirien/my-claude-apm-setup}"
APM_REF="${ISK_APM_SETUP_REF:-v0.6.1}"
APM_VERSION="${ISK_APM_VERSION:-0.28.0}"
SETUP_DIR="${ISK_APM_SETUP_DIR:-$HOME/.claude-apm-setup}"
CLAUDE_HOME="$HOME/.claude"

# --- 1. APM CLI (pinned + SHA256-verified) ---------------------------------
# Never install "latest": apm behaviour shifts between releases (0.27.0 began
# rejecting root-level skill deps, which broke `apm install --frozen` until the
# setup vendored the humanizer skill in v0.6.1). Pin + verify like the other
# core tools and bump ISK_APM_VERSION deliberately.
if have apm && apm --version 2>/dev/null | grep -qF " ${APM_VERSION} "; then
  log "apm ${APM_VERSION} already installed"
else
  apm_asset="apm-linux-$(apm_arch).tar.gz"
  apm_url="https://github.com/microsoft/apm/releases/download/v${APM_VERSION}/${apm_asset}"
  apm_tmp="$(mktemp -d)"
  log "installing APM CLI ${APM_VERSION} (${apm_asset})"
  fetch "$apm_url" "$apm_tmp/$apm_asset"
  fetch "$apm_url.sha256" "$apm_tmp/$apm_asset.sha256"
  verify_from_sums "$apm_tmp/$apm_asset" "$apm_asset" "$apm_tmp/$apm_asset.sha256"
  as_root rm -rf /usr/local/lib/apm-cli
  as_root mkdir -p /usr/local/lib/apm-cli
  as_root tar -xzf "$apm_tmp/$apm_asset" -C /usr/local/lib/apm-cli --strip-components=1
  as_root ln -sf /usr/local/lib/apm-cli/apm /usr/local/bin/apm
  rm -rf "$apm_tmp"
fi
have apm || die "apm not on PATH after install"

# --- 2. Clone / update the setup repo at the pinned ref --------------------
if [ ! -d "$SETUP_DIR/.git" ]; then
  log "cloning ${APM_REPO} @ ${APM_REF} -> ${SETUP_DIR}"
  git clone --depth 1 --branch "$APM_REF" "https://github.com/${APM_REPO}.git" "$SETUP_DIR" 2>/dev/null \
    || { warn "ref '${APM_REF}' not found; cloning default branch"; git clone --depth 1 "https://github.com/${APM_REPO}.git" "$SETUP_DIR"; }
else
  log "updating ${SETUP_DIR}"
  git -C "$SETUP_DIR" fetch --depth 1 --tags origin "$APM_REF" 2>/dev/null \
    && git -C "$SETUP_DIR" checkout -q FETCH_HEAD 2>/dev/null || warn "could not update to ${APM_REF}; using existing checkout"
fi

# --- 3. Materialize with APM (reproducible from the lockfile) --------------
log "running 'apm install --frozen' in ${SETUP_DIR}"
( cd "$SETUP_DIR" && apm install --frozen )

# --- 4. Mirror skills / agents / rules into ~/.claude (user scope) ---------
mkdir -p "$CLAUDE_HOME/skills" "$CLAUDE_HOME/agents" "$CLAUDE_HOME/rules"
[ -d "$SETUP_DIR/.claude/skills" ] && cp -a "$SETUP_DIR/.claude/skills/." "$CLAUDE_HOME/skills/"
[ -d "$SETUP_DIR/.claude/agents" ] && cp -a "$SETUP_DIR/.claude/agents/." "$CLAUDE_HOME/agents/"
[ -d "$SETUP_DIR/.claude/rules" ]  && cp -a "$SETUP_DIR/.claude/rules/."  "$CLAUDE_HOME/rules/"
[ -f "$SETUP_DIR/.lsp.json" ]      && cp -f "$SETUP_DIR/.lsp.json" "$CLAUDE_HOME/.lsp.json"
log "mirrored $(find "$CLAUDE_HOME/skills" -maxdepth 1 -mindepth 1 -type d | wc -l) skills, $(find "$CLAUDE_HOME/agents" -maxdepth 1 -name '*.md' | wc -l) agents into ${CLAUDE_HOME}"
# --- 5. Managed block in ~/.claude/CLAUDE.md importing the rules -----------
CLAUDE_MD="$CLAUDE_HOME/CLAUDE.md"
BEGIN="<!-- infrastructure-sandbox-kit:begin -->"
END="<!-- infrastructure-sandbox-kit:end -->"
touch "$CLAUDE_MD"
# strip any previous managed block, then append a fresh one
tmp_md="$(mktemp)"
awk -v b="$BEGIN" -v e="$END" '
  $0==b {skip=1} skip && $0==e {skip=0; next} !skip {print}
' "$CLAUDE_MD" > "$tmp_md" || true
{
  cat "$tmp_md"
  printf '%s\n' "$BEGIN"
  printf '# APM setup (dirien/my-claude-apm-setup)\n\n'
  printf 'Skills, subagents and guardrail hooks from this setup are active globally.\n'
  printf 'Project rules imported from this setup:\n\n'
  for r in "$CLAUDE_HOME"/rules/*.md; do
    [ -e "$r" ] || continue
    printf '@%s\n' "rules/$(basename "$r")"
  done
  printf '%s\n' "$END"
} > "$CLAUDE_MD"
rm -f "$tmp_md"

# --- 6. Apply guardrail hooks + MCP (shared with the setup.startup step) --
# Runs the same idempotent apply that fires on every sandbox start, so the hooks
# and MCP servers are present right after provisioning too.
ISK_APM_SETUP_DIR="$SETUP_DIR" bash "$SCRIPT_DIR/apply-agent-config.sh"

log "APM home setup complete"
