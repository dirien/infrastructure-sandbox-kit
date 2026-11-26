#!/usr/bin/env bash
# install-toolchains.sh — developer tooling for Pulumi across languages.
#
# The Ubuntu template image ships Go, Node and Python (+uv). The Debian-based
# claude workload (sbx >= 0.51) ships Python only, so Go and Node.js + npm are
# added from its apt sources first (ISK_GO_APT_PACKAGE / ISK_NODE_APT_PACKAGE).
# On top of that this adds the language servers referenced by
# dirien/my-claude-apm-setup's .lsp.json plus golangci-lint, and — opt-in via
# ISK_INSTALL_DOTNET=1 — the .NET SDK and csharp-ls for Pulumi C#/.NET.
#
# Everything is idempotent (guarded by `have`) and non-fatal. Go binaries install
# into ~/.local/bin (already on PATH).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

export GOBIN="$HOME/.local/bin"
mkdir -p "$GOBIN"

# --- Runtimes: Go, Node.js + npm (only when the base lacks them) -----------
# The package names are the Docker Hardened Images Debian ones (dhi.io), which
# track current Go and Node.js LTS releases; Debian's own golang-go/nodejs are
# too old for gopls@latest.
apt_updated=0
apt_install_missing() {
  have apt-get || { warn "no apt-get; cannot install $*"; return 1; }
  if [ "$apt_updated" = 0 ]; then
    as_root apt-get update -qq >/dev/null || return 1
    apt_updated=1
  fi
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$@" >/dev/null
}
if ! have go; then
  pkg="${ISK_GO_APT_PACKAGE:-golang-1.26}"
  log "installing Go (${pkg})"
  apt_install_missing "$pkg" || warn "Go install failed (non-fatal; gopls and golangci-lint are skipped)"
fi
if ! have node || ! have npm; then
  pkg="${ISK_NODE_APT_PACKAGE:-nodejs-24}"
  log "installing Node.js + npm (${pkg} npm)"
  apt_install_missing "$pkg" npm || warn "Node.js install failed (non-fatal; the npm language servers are skipped)"
fi

# The workload may export a GOPATH (e.g. /go) without creating it; module
# downloads and `go install` then fail for the agent user.
if have go && [ -n "${GOPATH:-}" ] && [ ! -w "$GOPATH" ]; then
  as_root install -d -o "$(id -u)" -g "$(id -g)" "$GOPATH" "$GOPATH/bin" "$GOPATH/pkg" \
    || warn "could not create GOPATH $GOPATH"
fi

# --- Go: gopls (LSP) + golangci-lint --------------------------------------
if have go && ! have gopls; then
  log "installing gopls -> $GOBIN"
  go install golang.org/x/tools/gopls@latest || warn "gopls install failed (non-fatal)"
fi
if ! have golangci-lint; then
  log "installing golangci-lint -> $GOBIN"
  curl -fsSL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh \
    | sh -s -- -b "$GOBIN" >/dev/null 2>&1 || warn "golangci-lint install failed (non-fatal)"
fi

# --- Node/TypeScript + Python language servers (via npm) -------------------
if have npm && ! have typescript-language-server; then
  log "installing typescript + typescript-language-server"
  npm_g typescript typescript-language-server || warn "typescript-language-server install failed (non-fatal)"
fi
if have npm && ! have pyright; then
  log "installing pyright"
  npm_g pyright || warn "pyright install failed (non-fatal)"
fi

# --- Optional: .NET SDK + csharp-ls for Pulumi C#/.NET ---------------------
# Heavy (~700MB). Off by default; enable with ISK_INSTALL_DOTNET=1.
if [ "${ISK_INSTALL_DOTNET:-0}" = "1" ]; then
  if ! have dotnet; then
    channel="${ISK_DOTNET_CHANNEL:-8.0}"
    log "installing .NET SDK ${channel}"
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    fetch "https://dot.net/v1/dotnet-install.sh" "$tmp/dotnet-install.sh"
    dotnet_root="/usr/share/dotnet"
    as_root bash "$tmp/dotnet-install.sh" --channel "$channel" --install-dir "$dotnet_root" --no-path
    as_root ln -sf "$dotnet_root/dotnet" /usr/local/bin/dotnet
  fi
  if have dotnet && ! have csharp-ls; then
    log "installing csharp-ls"
    dotnet tool install -g csharp-ls >/dev/null 2>&1 || warn "csharp-ls install failed (non-fatal)"
  fi
fi
