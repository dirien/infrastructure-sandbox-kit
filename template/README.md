# Infrastructure sandbox template

A prebuilt sandbox image: `docker/sandbox-templates:claude-code-docker` with the
full IaC toolchain (Pulumi, Terraform, OpenTofu, and the AWS/Azure/gcloud CLIs)
and `dirien/my-claude-apm-setup` baked in, so sandboxes start with the tools
already installed. The [`../sandbox-kit`](../sandbox-kit) artifact names this
image and adds the network rules, the Pulumi credential injection, the MCP
servers and the agent instructions, all in a single `--kit` flag.

## Build

Build from the repo root, since the Dockerfile needs the shared `../scripts/` tree
in the build context:

`make build` stamps the image with both its version tag (`VERSION`, default the
latest git tag) and `:latest`.

```bash
# from the repo root
make build                         # -> infrastructure-sandbox:v0.11.1 and :latest
make build INSTALL_CLOUDS=0        # leaner: skip the AWS/Azure/gcloud CLIs
make build INSTALL_DOTNET=1        # also install the .NET SDK + csharp-ls for Pulumi C#
# or directly:
DOCKER_BUILDKIT=1 docker build -f template/Dockerfile \
  -t infrastructure-sandbox:v0.11.1 -t infrastructure-sandbox:latest .
```

Build args (all pinned; override with `--build-arg`):

| Arg | Default | Purpose |
|---|---|---|
| `BASE` | `docker/sandbox-templates:claude-code-docker` | base sandbox image |
| `ISK_PULUMI_VERSION` | `3.273.0` | Pulumi CLI |
| `ISK_TERRAFORM_VERSION` | `1.17.1` | Terraform |
| `ISK_OPENTOFU_VERSION` | `1.13.2` | OpenTofu |
| `ISK_KUBECTL_VERSION` | `1.37.2` | kubectl |
| `ISK_HELM_VERSION` | `4.3.1` | Helm |
| `ISK_AWSCLI_VERSION` | `2.39.3` | AWS CLI v2 |
| `ISK_AZ_APT_DIST` | `resolute` | Microsoft azure-cli apt dist (Ubuntu 26.04, like the base image) |
| `ISK_INSTALL_CLOUDS` | `1` | `0` drops the AWS/Azure/gcloud CLIs |
| `ISK_APM_SETUP_REPO` / `ISK_APM_SETUP_REF` | `dirien/my-claude-apm-setup` / `v0.7.0` | APM setup |
| `ISK_APM_VERSION` | `0.39.0` | APM CLI (pinned + SHA256; bump deliberately) |
| `ISK_INSTALL_DOTNET` / `ISK_DOTNET_CHANNEL` | `0` / `8.0` | .NET SDK + csharp-ls |

## Use it

The published image is what [`../sandbox-kit`](../sandbox-kit) names, so
`make run` (the sandbox kit plus the runbooks from `kit/files/`) uses it without a local build. To run a
locally built variant, load it into sbx's template store and point a copy of
the sandbox kit at it:

```bash
make load                          # build + docker save (both tags) + sbx template load
cp -R sandbox-kit /tmp/my-sandbox-kit && cp -R kit/files /tmp/my-sandbox-kit/files
# edit /tmp/my-sandbox-kit/spec.yaml: sandbox.image: infrastructure-sandbox:v0.11.1
sbx run /tmp/my-sandbox-kit .
```

Or publish to a registry (pushes `:v0.11.1` and `:latest`) and set
`sandbox.image` to that reference:

```bash
make build push IMAGE=ghcr.io/dirien/infrastructure-sandbox
```

The image provides the tools, so the sandbox kit's install step is a fast
sentinel no-op, and the kit contributes the network allow-list, the
`PULUMI_ACCESS_TOKEN` injection, the Pulumi MCP and the agent instructions.
The image can't be combined with the [`../kit`](../kit) mixin any more: the
mixin is a kit-spec v3 kit for Docker's built-in `claude` agent, and sbx 0.51+
refuses `--template … --kit ./kit claude`.

## What's baked in

- `pulumi` in `/opt/pulumi` (symlinked onto `PATH`, with the bundled
  `pulumi-language-*` and `pulumi-resource-*` plugins), `terraform`, `tofu`,
  `kubectl`, `helm`, and, unless `INSTALL_CLOUDS=0`, `aws`, `az` and `gcloud`.
- `gopls`, `golangci-lint` (in `~/.local/bin`), `typescript-language-server` and
  `pyright`. Building with `INSTALL_DOTNET=1` adds `csharp-ls` and the .NET SDK.
- `apm` (`/usr/local/bin/apm`) and `dirien/my-claude-apm-setup` cloned to
  `~/.claude-apm-setup`, materialized into `~/.claude` (skills, agents, rules,
  hooks), with the MCP servers registered at user scope in `~/.claude.json`.
- A provisioning sentinel at `~/.local/state/infrastructure-sandbox-kit/provisioned`
  so the kit's create-time install is skipped on this image.

Docker reseeds `~/.claude/settings.json` and `~/.claude.json` when it creates a
sandbox, which would wipe the baked-in hooks and MCP config. The sandbox kit's
`setup.startup` re-applies them on every start, so run the image through the
sandbox kit to keep the guardrail hooks and MCP servers active. The skills,
subagents and rules survive the reseed on their own.

Reference build: about 6.6 GB with the cloud CLIs, about 4.2 GB with
`INSTALL_CLOUDS=0`.

## How the base was chosen

`claude-code-docker` (Ubuntu 26.04) already ships Node 22, Python 3.14 (with uv),
Java 25, Go, Docker, `git`, `gh` and Claude Code, running as `agent`
(uid 1000) with passwordless sudo. The template only adds the IaC tooling on top,
and provisioning runs as `agent` so the APM and Claude config lands in
`/home/agent` with the right ownership. Swap `BASE` to `claude-code` (no
Docker-in-Docker) if you don't need to build containers inside the sandbox.
