#!/usr/bin/env bash
# apply-agent-config.sh — (re)apply the APM guardrail hooks and MCP servers into
# the agent's user-scope Claude config.
#
# Docker reseeds ~/.claude/settings.json and ~/.claude.json when it creates a
# sandbox, which wipes anything the image baked in. So this runs as a
# commands.startup step (after that reseed, on every start) to keep the hooks and
# MCP servers present. It is idempotent: hooks are deduped and MCP servers are
# removed-then-added. Skills, subagents and rules under ~/.claude survive the
# reseed and are placed by setup-apm-home.sh.
#
# Self-contained (bash, python3, the claude CLI); no lib.sh dependency so it stays
# robust when invoked directly at startup.
set -euo pipefail

tag="[infrastructure-sandbox-kit]"
log() { printf '%s %s\n' "$tag" "$*" >&2; }

SETUP_DIR="${ISK_APM_SETUP_DIR:-$HOME/.claude-apm-setup}"
CLAUDE_HOME="$HOME/.claude"

if [ ! -d "$SETUP_DIR/.claude" ]; then
  log "apm setup not present at $SETUP_DIR; skipping agent-config apply"
  exit 0
fi

# --- Guardrail hooks into ~/.claude/settings.json (absolute paths) ----------
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
print("[infrastructure-sandbox-kit] wired guardrail hooks -> " + dst_path)
PY
fi

# --- MCP servers at user scope ---------------------------------------------
if command -v claude >/dev/null 2>&1 && [ -f "$SETUP_DIR/.mcp.json" ]; then
  while IFS=$'\t' read -r name cfg; do
    [ -n "$name" ] || continue
    log "registering MCP server '$name' (user scope)"
    timeout 60 claude mcp remove -s user "$name"  >/dev/null 2>&1 || true
    timeout 60 claude mcp add-json -s user "$name" "$cfg" >/dev/null 2>&1 \
      || log "WARN: could not register MCP server '$name' (add later: claude mcp add-json -s user $name '<json>')"
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

log "agent config applied (hooks + MCP)"
