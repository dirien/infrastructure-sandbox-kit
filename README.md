# infrastructure-sandbox-kit

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) template and kit that
sets up a Claude Code sandbox for Infrastructure-as-Code work. It installs Pulumi,
Terraform, OpenTofu and the AWS, Azure and Google Cloud CLIs, and wires
[`dirien/my-claude-apm-setup`](https://github.com/dirien/my-claude-apm-setup)
(APM) into the agent home so it is active in every workspace.

The sandbox comes with:

- Pulumi CLI, Terraform, and OpenTofu, each pinned to a version and verified by
  checksum or signature. Pulumi ships with its bundled language plugins, and ESC is
  available through `pulumi env` (the standalone `esc` CLI was retired in 2026).
- kubectl and Helm, pinned and checksum-verified the same way, for the
  Kubernetes side of IaC work.
- The AWS CLI v2, Azure CLI and gcloud. Set `INSTALL_CLOUDS=0` to skip them.
- The language runtimes from the base image (Go, Node, Python, Java) plus the
  language servers `gopls`, `typescript-language-server`, `pyright` and
  `golangci-lint`. Enabling .NET adds `csharp-ls` and the .NET SDK.
- The Pulumi Cloud token, injected by the sandbox credential proxy. The container
  only ever sees `PULUMI_ACCESS_TOKEN=proxy-managed`.
- The `pulumi` MCP server at user scope (registry lookups, schema and code
  validation, Neo).
- The APM setup in `~/.claude` for every workspace: 34 skills (including the
  official Pulumi skills, `terraform-skill` with its `code-intelligence`
  companion, and `shellcheck-configuration`), 3 subagents, the instruction
  rules, and two guardrail hooks. One blocks destructive shell
  commands; the other scans edits for secrets and formats them.

## Three ways to use it

| | Sandbox kit (one flag) | Template + mixin | Mixin only |
|---|---|---|---|
| What | One OCI artifact that names the prebuilt image and carries all the rules | The prebuilt image plus the `kit/` mixin | The stock `claude` image plus the `kit/` mixin, installed at create time |
| Speed | Instant sandbox starts | Instant sandbox starts | A few minutes on first create (downloads + APM) |
| Needs | nothing (published on GHCR) | one image build, or the published image | nothing |

Every path applies the same declarations: the network rules, the Pulumi
credential, the MCP servers and the agent instructions. The mixin paths run the
built-in `claude` agent, so Claude's own auth is untouched; the sandbox kit
defines the agent itself and pins the image (see [`sandbox-kit/`](sandbox-kit)).

## Prerequisites

- [`sbx`](https://github.com/docker/sbx-releases) ≥ 0.38.0 and Docker on your
  host. The sandbox CLI is a host tool. Kits are experimental, and this kit uses
  the v2 spec schema that landed in 0.38.0, so keep `sbx` current.
- A Pulumi Cloud access token, and whatever cloud credentials your stacks need
  (see [`docs/credentials.md`](docs/credentials.md)).

## Run it

### One artifact: the sandbox kit

```bash
sbx secret set -g pulumi           # one-time: bind your Pulumi token (docs/credentials.md)
sbx run --kit ghcr.io/dirien/infrastructure-sandbox-kit:latest .
```

The kit names the template image and carries every rule, so there is nothing
else to pass. A sandbox kit defines the agent itself; if your `sbx` build still
expects an agent name, use `infrastructure-sandbox`. Details in
[`sandbox-kit/`](sandbox-kit).

### On the prebuilt template image

The image is stamped with both its version tag (`:v0.6.1`) and `:latest`.

```bash
make load                          # build + load into sbx (as :v0.6.1 and :latest)
#   leaner (no cloud CLIs):  make load INSTALL_CLOUDS=0
#   add .NET (Pulumi C#):    make load INSTALL_DOTNET=1

sbx secret set -g pulumi           # one-time: bind your Pulumi token (docs/credentials.md)

make run                           # sbx run --template infrastructure-sandbox:v0.6.1 --kit ./kit claude .
```

Or push to a registry (as `:v0.6.1` and `:latest`) and point `--template` at it:

```bash
make build push IMAGE=ghcr.io/dirien/infrastructure-sandbox        # + VERSION=v0.6.1 to override
sbx run --template ghcr.io/dirien/infrastructure-sandbox:v0.6.1 --kit ./kit claude .
```

### Kit only, no image build

The kit is published to GHCR by the `publish-kit` workflow, and it also runs
straight from git or from a local clone. Pick whichever fits:

```bash
# From the published kit on GHCR:
sbx run --kit ghcr.io/dirien/infrastructure-kit:latest claude .

# Straight from this repo over git:
sbx run --kit "git+https://github.com/dirien/infrastructure-sandbox-kit.git#dir=kit" claude .

# From a local clone (the kit lives under kit/):
git clone https://github.com/dirien/infrastructure-sandbox-kit.git
sbx run --kit ./infrastructure-sandbox-kit/kit claude .
```

By default `sbx` only allows kits from `docker.io/`. Authorize the GHCR and GitHub
sources once on your host (local `./kit` paths are allowed by default):

```bash
sbx settings set kit.allowedSources '["docker.io/","ghcr.io/dirien/","github.com/dirien/"]'
```

On the stock `claude` image the kit installs the toolchain at create time, which
takes a few minutes.

Reproducibility: the kit fetches its provisioning scripts from `KIT_REF` in
`kit/spec.yaml`, which is pinned to an immutable release tag (`v0.6.1`), not a
moving branch — so the scripts don't change under you even if you fetch the kit
from `main`. `make publish-kit` goes further and rewrites `KIT_REF` to the exact
commit SHA in the OCI artifact. To pin a git run to a different release, use
`…&ref=<tag>` and `make pin REF=<tag>` (which sets `KIT_REF` to match).

Once the sandbox is up, `~/runbooks/` holds credential-free Pulumi and
Terraform/OpenTofu starters:

```bash
cd ~/runbooks/terraform-random && terraform init && terraform plan
```

## Install hardening

The core IaC tools are installed from a pinned version and verified by checksum
or signature, no `curl | sh`. That covers Pulumi and ESC, Terraform, OpenTofu,
kubectl and Helm, the AWS CLI (pinned + SHA256), Azure CLI and gcloud (GPG-signed vendor apt
repos), and the APM CLI (pinned release tarball + published SHA256 — apm's
behaviour shifts between releases, so installing "latest" is a hazard).
The language servers and `golangci-lint` use their vendors' installers
(`go install`, `npm`), so those are not version-pinned.

| Tool | Method | Verification |
|---|---|---|
| Pulumi CLI | GitHub release tarball | pinned per-arch SHA256 |
| Terraform | HashiCorp releases | published SHA256SUMS |
| OpenTofu | GitHub release | published SHA256SUMS |
| kubectl | dl.k8s.io release binary | published per-binary SHA256 |
| Helm | get.helm.sh tarball | published SHA256 |
| AWS CLI v2 | official installer zip | pinned per-arch SHA256 |
| Azure CLI | Microsoft apt repo | GPG-signed (apt) |
| gcloud | Google Cloud apt repo | GPG-signed (apt) |
| APM CLI | GitHub release tarball | pinned + published SHA256 |

## What "APM in the agent home" means here

`dirien/my-claude-apm-setup` is normally consumed per repo with `apm install`.
This kit instead materializes it at user scope, so it applies in every workspace
opened in the sandbox without a per-project `apm.yml`:

| Materialized to | From the setup |
|---|---|
| `~/.claude/skills/*` | 34 pinned skills |
| `~/.claude/agents/*` | `executor`, `librarian`, `reviewer` subagents |
| `~/.claude/rules/*` + a managed block in `~/.claude/CLAUDE.md` | the instruction rules |
| `~/.claude/settings.json` | the PreToolUse guard + PostToolUse secret-scan/format hooks, rewritten to absolute paths so they fire in any workspace |
| `~/.claude.json` (user scope) | the `pulumi` MCP server |

To update it later, run `git -C ~/.claude-apm-setup pull && ISK_FORCE=1 ~/.local/share/infrastructure-sandbox-kit/scripts/provision.sh`.

## Layout

```
infrastructure-sandbox-kit/
├── kit/spec.yaml              # the mixin kit: kind: mixin, schemaVersion "2"
├── sandbox-kit/spec.yaml      # the one-flag bundle: kind: sandbox, pins the image + same rules
├── template/Dockerfile        # the baked image (FROM claude-code-docker)
├── scripts/                   # canonical provisioning, shared by both paths
│   ├── lib.sh                 #   shared helpers (arch, fetch, verify)
│   ├── install-pulumi.sh      #   Pulumi CLI (pinned, SHA256-verified)
│   ├── install-iac.sh         #   Terraform + OpenTofu (SHA256SUMS-verified)
│   ├── install-clouds.sh      #   AWS (pinned SHA) + Azure/gcloud (GPG apt), per-component
│   ├── install-toolchains.sh  #   gopls / tsserver / pyright / golangci-lint (+ optional .NET)
│   ├── setup-apm-home.sh      #   APM + my-claude-apm-setup into ~/.claude
│   ├── apply-agent-config.sh  #   (re)apply guardrail hooks + MCP (idempotent)
│   ├── provision.sh           #   orchestrator (sentinel-guarded, idempotent)
│   ├── startup.sh             #   setup.startup: re-apply config + retry missing clouds
│   └── push-kit.sh            #   publish the kit to an OCI registry
├── docs/credentials.md        # binding Pulumi / cloud creds
├── docs/network.md            # extending the allow-list for your clouds
└── Makefile                   # build / load / push / validate / run / pin
```

## Pinned versions

| Component | Default | Where to change |
|---|---|---|
| Pulumi CLI | `3.255.0` | `scripts/install-pulumi.sh` (+ SHA256s), `kit/spec.yaml`, `Makefile` |
| Terraform | `1.15.8` | `scripts/install-iac.sh`, `kit/spec.yaml`, `Makefile` |
| OpenTofu | `1.12.5` | same |
| kubectl | `1.36.3` | same |
| Helm | `4.2.3` | same |
| AWS CLI v2 | `2.36.10` | `scripts/install-clouds.sh` (+ SHA256s), `kit/spec.yaml`, `Makefile` |
| Azure CLI / gcloud | latest (GPG apt) | vendor repos; az dist pinned via `AZ_APT_DIST` (`noble`) |
| my-claude-apm-setup | `v0.6.2` | `ISK_APM_SETUP_REF` |
| APM CLI | `0.28.0` | `ISK_APM_VERSION` (pinned + SHA256; bump deliberately) |
| Base image | `docker/sandbox-templates:claude-code-docker` | `BASE` build arg |

`make help` lists every target. Validate with `make validate` (`sbx kit validate ./kit`).

## How this compares

Measured against [ajeetraina's `sbx-kits-*`](https://github.com/ajeetraina?tab=repositories&q=sbx-kits)
collection (Firecrawl, mem0, SurrealDB, Grafana, Dagger, VS Code, and others):

- It is the first IaC kit. Nothing in his `awesome-docker-sbx` catalog covers
  Pulumi, Terraform or OpenTofu; those kits each wrap a single tool.
- The core IaC tools are pinned and verified by SHA256 or a GPG signature (see
  the hardening table). The community kits mostly install with `curl | sh` or
  `pip install ==x`.
- No other kit wires a whole agent-config framework (skills, subagents, hooks,
  MCP) into `~/.claude`.
- It borrows two things from his kits: OCI publishing (`sbx kit push` to GHCR, via
  `.github/workflows/publish-kit.yaml`) and starter runbook files
  (`kit/files/home/runbooks/`).

## Notes and limitations

- Cloud endpoints beyond the starters must be added per provider and region to
  the `permissions.network.allow` list in `kit/spec.yaml`. Kit-level enforcement
  covers exact hosts, `host:port` and single-label `*.host` patterns; `**.host`
  and CIDR parse but aren't enforced yet. See [`docs/network.md`](docs/network.md).
- Cloud auth is not baked in. `aws`, `az` and `gcloud` need credentials supplied
  at run time or through Pulumi ESC. AWS uses SigV4, so its credentials stay in
  the container. See [`docs/credentials.md`](docs/credentials.md).
- Kits are experimental. The kit targets the kit-spec v2 grammar introduced in
  Docker Sandboxes 0.38.0 (`schemaVersion: "2"`: `permissions.network`,
  `credentials`, `setup`, `agentInstructions`) from Docker's
  [kit reference](https://docs.docker.com/ai/sandboxes/customize/kit-reference/).
  The v2 loader is strict — leftover v1 fields are decode errors — while v1 kits
  still load through a legacy path. `sbx` is a host tool that isn't available in
  every environment, so validate on your host with `sbx kit validate ./kit`.

## License

MIT. See [`LICENSE`](LICENSE).
