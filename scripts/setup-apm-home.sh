#!/usr/bin/env bash
# setup-apm-home.sh — install APM and materialize dirien/my-claude-apm-setup into
# the agent's USER-GLOBAL Claude config (~/.claude), so the skills, subagents,
# rules, guardrail hooks and MCP servers are active in *every* workspace opened
# in the sandbox — "out of the box", no per-repo apm.yml required.
#
# What it wires (all idempotent):
#   ~/.claude/skills/*         <- the 23 pinned APM skills
#   ~/.claude/agents/*         <- executor / librarian / reviewer subagents
#   ~/.claude/rules/*          <- the instruction rules
#   ~/.claude/CLAUDE.md        <- a managed block importing those rules
#   ~/.claude/settings.json    <- PreToolUse guard + PostToolUse format/secret hooks
#                                 (paths rewritten to absolute so they work anywhere)
#   ~/.claude.json mcpServers  <- context7 + pulumi MCP at USER scope (claude mcp add-json)
#   ~/.claude/.lsp.json        <- APM's language-server config (best-effort)
#
# Runs as the agent user. Re-runnable; safe to call again after `git pull`.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

APM_REPO="${ISK_APM_SETUP_REPO:-dirien/my-claude-apm-setup}"
APM_REF="${ISK_APM_SETUP_REF:-v0.4.0}"
SETUP_DIR="${ISK_APM_SETUP_DIR:-$HOME/.claude-apm-setup}"
CLAUDE_HOME="$HOME/.claude"

# --- 1. APM CLI ------------------------------------------------------------
if ! have apm; then
  log "installing APM CLI"
  curl -fsSL https://aka.ms/apm-unix | sh
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

# --- 6. Merge guardrail hooks into ~/.claude/settings.json -----------------
# The APM-generated hooks reference ${CLAUDE_PROJECT_DIR:-.}/scripts/*.sh; rewrite
# to the absolute setup path so they fire in any workspace, then merge (dedup by
# event+matcher+command) into whatever user settings already exist.
SRC_SETTINGS="$SETUP_DIR/.claude/settings.json"
if [ -f "$SRC_SETTINGS" ]; then
  SETUP_DIR="$SETUP_DIR" DST="$CLAUDE_HOME/settings.json" SRC="$SRC_SETTINGS" python3 - <<'PY'
import json, os
setup_dir = os.environ["SETUP_DIR"]
dst_path  = os.environ["DST"]
src_path  = os.environ["SRC"]

def load(p):
    try:
        with open(p) as f:
            return json.load(f)
    except Exception:
        return {}

src = load(src_path)
dst = load(dst_path)
dst.setdefault("hooks", {})

def rewrite(cmd: str) -> str:
    return cmd.replace("${CLAUDE_PROJECT_DIR:-.}", setup_dir).replace("$CLAUDE_PROJECT_DIR", setup_dir)

for event, groups in (src.get("hooks") or {}).items():
    existing = dst["hooks"].setdefault(event, [])
    seen = {
        (g.get("matcher", ""), h.get("command", ""))
        for g in existing for h in (g.get("hooks") or [])
    }
    for g in groups:
        hooks = []
        for h in (g.get("hooks") or []):
            h = dict(h)
            if h.get("type") == "command" and "command" in h:
                h["command"] = rewrite(h["command"])
            key = (g.get("matcher", ""), h.get("command", ""))
            if key in seen:
                continue
            seen.add(key)
            hooks.append(h)
        if hooks:
            existing.append({"matcher": g.get("matcher", ""), "hooks": hooks})

os.makedirs(os.path.dirname(dst_path), exist_ok=True)
with open(dst_path, "w") as f:
    json.dump(dst, f, indent=2)
    f.write("\n")
print(f"[infrastructure-sandbox-kit] wired guardrail hooks -> {dst_path}")
PY
fi

# --- 7. Register the MCP servers at USER scope -----------------------------
# Read the servers APM configured (SETUP_DIR/.mcp.json) and register each at user
# scope with the Claude CLI, so they are available in every workspace.
if have claude && [ -f "$SETUP_DIR/.mcp.json" ]; then
  while IFS=$'\t' read -r name cfg; do
    [ -n "$name" ] || continue
    log "registering MCP server '${name}' (user scope)"
    timeout 60 claude mcp remove -s user "$name"  >/dev/null 2>&1 || true
    timeout 60 claude mcp add-json -s user "$name" "$cfg" >/dev/null 2>&1 \
      || warn "could not register MCP server '${name}' (add it later with: claude mcp add-json -s user ${name} '<json>')"
  done < <(python3 - "$SETUP_DIR/.mcp.json" <<'PY'
import json, sys
try:
    servers = json.load(open(sys.argv[1])).get("mcpServers", {})
except Exception:
    servers = {}
for name, cfg in servers.items():
    print(name + "\t" + json.dumps(cfg, separators=(",", ":")))
PY
)
fi

log "APM home setup complete"
