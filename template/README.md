# Pulumi sandbox template

A prebuilt sandbox image — `docker/sandbox-templates:claude-code-docker` with the
Pulumi toolchain and `dirien/my-claude-apm-setup` baked in, so sandboxes start
instantly with everything already in place. This is the recommended ("perfect
template") path; the [`../kit`](../kit) mixin adds the Pulumi network rules,
credential injection, MCP and agent context on top.

## Build

Build from the **repo root** (the Dockerfile needs the shared `../scripts/` tree
in the build context):

```bash
# from the repo root
make build                         # DOCKER_BUILDKIT docker build -f template/Dockerfile -t pulumi-sandbox:latest .
make build INSTALL_DOTNET=1        # also install the .NET SDK + csharp-ls for Pulumi C#
# or directly:
DOCKER_BUILDKIT=1 docker build -f template/Dockerfile -t pulumi-sandbox:latest .
```

Build args (all pinned; override with `--build-arg`):

| Arg | Default | Purpose |
|---|---|---|
| `BASE` | `docker/sandbox-templates:claude-code-docker` | base sandbox image |
| `PSK_PULUMI_VERSION` | `3.255.0` | Pulumi CLI version |
| `PSK_ESC_VERSION` | `0.26.0` | Pulumi ESC version |
| `PSK_APM_SETUP_REPO` | `dirien/my-claude-apm-setup` | APM setup repo |
| `PSK_APM_SETUP_REF` | `v0.4.0` | APM setup ref (tag/branch/SHA) |
| `PSK_INSTALL_DOTNET` | `0` | `1` installs the .NET SDK + csharp-ls |
| `PSK_DOTNET_CHANNEL` | `8.0` | .NET SDK channel when enabled |

## Use it

Load into sbx's local template store (no registry needed):

```bash
make load                          # build + docker save + sbx template load
sbx run --template pulumi-sandbox:latest --kit ../kit claude .
```

Or publish to a registry and reference it there:

```bash
make build push IMAGE=ghcr.io/dirien/pulumi-sandbox:v1
sbx run --template ghcr.io/dirien/pulumi-sandbox:v1 --kit ../kit claude .
```

Running the template **with** the kit is the intended combination: the image
provides the tools (so the kit's install step is a fast sentinel no-op), and the
kit contributes the Pulumi allow-list, the `PULUMI_ACCESS_TOKEN` injection, the
Pulumi MCP and the agent context.

## What's baked in

- `pulumi` + `esc` in `/opt/pulumi`, symlinked onto `PATH`, with the bundled
  `pulumi-language-*` / `pulumi-resource-*` plugins.
- `gopls`, `golangci-lint` (in `~/.local/bin`), `typescript-language-server`,
  `pyright` — and `csharp-ls` + the .NET SDK when built with `INSTALL_DOTNET=1`.
- `apm` (`/usr/local/bin/apm`) and `dirien/my-claude-apm-setup` cloned to
  `~/.claude-apm-setup`, materialized into `~/.claude` (skills, agents, rules,
  hooks) with MCP registered at user scope in `~/.claude.json`.
- A provisioning sentinel at `~/.local/state/pulumi-sandbox-kit/provisioned` so
  the kit's create-time install is skipped on this image.

## How the base was chosen

`claude-code-docker` (Ubuntu 26.04) already ships Node 22, Python 3.14 (+ uv),
Java 25, Go 1.26, Docker, `git`, `gh` and Claude Code, running as `agent`
(uid 1000) with passwordless sudo. The template only adds what Pulumi needs on
top; provisioning runs as `agent` so the APM/Claude config lands in `/home/agent`
owned correctly. Swap `BASE` to `claude-code` (no Docker-in-Docker) if you don't
need to build containers inside the sandbox.
