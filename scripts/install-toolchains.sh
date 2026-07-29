#!/usr/bin/env bash
# install-toolchains.sh — developer tooling for Pulumi across languages.
#
# The base image already ships Go, Node, Python (+uv) and Java. This adds the
# language servers referenced by dirien/my-claude-apm-setup's .lsp.json plus
# golangci-lint, and — opt-in via ISK_INSTALL_DOTNET=1 — the .NET SDK and
# csharp-ls for Pulumi C#/.NET.
#
# Everything is idempotent (guarded by `have`). Go binaries install into
# ~/.local/bin (already on PATH); /home/agent/go/bin is NOT on PATH in the base.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

export GOBIN="$HOME/.local/bin"
mkdir -p "$GOBIN"

# --- Go: gopls (LSP) + golangci-lint --------------------------------------
if ! have gopls; then
  log "installing gopls -> $GOBIN"
  go install golang.org/x/tools/gopls@latest || warn "gopls install failed (non-fatal)"
fi
if ! have golangci-lint; then
  log "installing golangci-lint -> $GOBIN"
  curl -fsSL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh \
    | sh -s -- -b "$GOBIN" >/dev/null 2>&1 || warn "golangci-lint install failed (non-fatal)"
fi

# --- Node/TypeScript + Python language servers (via npm) -------------------
if ! have typescript-language-server; then
  log "installing typescript + typescript-language-server"
  npm_g typescript typescript-language-server || warn "typescript-language-server install failed (non-fatal)"
fi
if ! have pyright; then
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
