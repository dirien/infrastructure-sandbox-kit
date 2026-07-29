# infrastructure-sandbox-kit

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) template and kit that
sets up a Claude Code sandbox for Infrastructure-as-Code work. It installs Pulumi,
Terraform, OpenTofu and the AWS, Azure and Google Cloud CLIs, and wires
[`dirien/my-claude-apm-setup`](https://github.com/dirien/my-claude-apm-setup)
(APM) into the agent home so it is active in every workspace.

The sandbox comes with:

- Pulumi CLI and ESC, Terraform, and OpenTofu, each pinned to a version and
  verified by checksum or signature. Pulumi ships with its bundled language plugins.
- The AWS CLI v2, Azure CLI and gcloud. Set `INSTALL_CLOUDS=0` to skip them.
- The language runtimes from the base image (Go, Node, Python, Java) plus the
  language servers `gopls`, `typescript-language-server`, `pyright` and
  `golangci-lint`. Enabling .NET adds `csharp-ls` and the .NET SDK.
- The Pulumi Cloud token, injected by the sandbox credential proxy. The container
  only ever sees `PULUMI_ACCESS_TOKEN=proxy-managed`.
- Two MCP servers at user scope: `pulumi` (registry lookups, schema and code
  validation, Neo) and `context7` (current library docs).
- The APM setup in `~/.claude` for every workspace: 23 skills, 3 subagents, the
  instruction rules, and two guardrail hooks. One blocks destructive shell
  commands; the other scans edits for secrets and formats them.

## Two ways to use it

| | Template (recommended) | Kit only |
|---|---|---|
| What | A prebuilt image with the tools baked in | The stock `claude` image plus this kit, installed at create time |
| Speed | Instant sandbox starts | A few minutes on first create (downloads + APM) |
| Needs | one image build | nothing, once the kit is published or pushed to GitHub |

Both run the built-in `claude` agent, so Claude's own auth is untouched, and both
apply the same `kit/` mixin for the network rules, the Pulumi credential, the MCP
servers and the agent context.

## Prerequisites

- [`sbx`](https://github.com/docker/sbx-releases) and Docker on your host. The
  sandbox CLI is a host tool. Kits are experimental, so keep `sbx` current.
- A Pulumi Cloud access token, and whatever cloud credentials your stacks need
  (see [`docs/credentials.md`](docs/credentials.md)).

## Run it

### On the prebuilt template image (recommended)

```bash
make load                          # docker build + sbx template load
#   leaner (no cloud CLIs):  make load INSTALL_CLOUDS=0
#   add .NET (Pulumi C#):    make load INSTALL_DOTNET=1

sbx secret set -g pulumi           # one-time: bind your Pulumi token (docs/credentials.md)

make run                           # sbx run --template infrastructure-sandbox:latest --kit ./kit claude .
```

Or push the image to a registry and point `--template` at it:

```bash
make build push IMAGE=ghcr.io/dirien/infrastructure-sandbox:v1
sbx run --template ghcr.io/dirien/infrastructure-sandbox:v1 --kit ./kit claude .
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

On the stock `claude` image the kit installs the toolchain at create time, which
takes a few minutes. For reproducible runs, pin the git URL with `&ref=v0.2.0`
and run `make pin REF=v0.2.0` so the fetched scripts match, or pin the OCI ref by
digest (`@sha256:...`).

Once the sandbox is up, `~/runbooks/` holds credential-free Pulumi and
Terraform/OpenTofu starters:

```bash
cd ~/runbooks/terraform-random && terraform init && terraform plan
```

## Install hardening

Every tool is installed from a pinned version and verified. There are no
`curl | sh` pipes, which is the main gap in the comparable community kits (see
[How this compares](#how-this-compares)).

| Tool | Method | Verification |
|---|---|---|
| Pulumi CLI + ESC | GitHub release tarball | pinned per-arch SHA256 |
| Terraform | HashiCorp releases | published SHA256SUMS |
| OpenTofu | GitHub release | published SHA256SUMS |
| AWS CLI v2 | official installer zip | pinned per-arch SHA256 |
| Azure CLI | Microsoft apt repo | GPG-signed (apt) |
| gcloud | Google Cloud apt repo | GPG-signed (apt) |

## What "APM in the agent home" means here

`dirien/my-claude-apm-setup` is normally consumed per repo with `apm install`.
This kit instead materializes it at user scope, so it applies in every workspace
opened in the sandbox without a per-project `apm.yml`:

| Materialized to | From the setup |
|---|---|
| `~/.claude/skills/*` | 23 pinned skills |
| `~/.claude/agents/*` | `executor`, `librarian`, `reviewer` subagents |
| `~/.claude/rules/*` + a managed block in `~/.claude/CLAUDE.md` | the instruction rules |
| `~/.claude/settings.json` | the PreToolUse guard + PostToolUse secret-scan/format hooks, rewritten to absolute paths so they fire in any workspace |
| `~/.claude.json` (user scope) | the `context7` and `pulumi` MCP servers |

To update it later, run `git -C ~/.claude-apm-setup pull && ISK_FORCE=1 ~/.local/share/infrastructure-sandbox-kit/scripts/provision.sh`.

## Layout

```
infrastructure-sandbox-kit/
├── kit/spec.yaml              # the kit: kind: mixin (schemaVersion "2"), requires claude
├── template/Dockerfile        # the baked image (FROM claude-code-docker)
├── scripts/                   # canonical provisioning, shared by both paths
│   ├── lib.sh                 #   shared helpers (arch, fetch, verify)
│   ├── install-pulumi.sh      #   Pulumi CLI + ESC (pinned, SHA256-verified)
│   ├── install-iac.sh         #   Terraform + OpenTofu (SHA256SUMS-verified)
│   ├── install-clouds.sh      #   AWS (pinned SHA) + Azure/gcloud (GPG apt)
│   ├── install-toolchains.sh  #   gopls / tsserver / pyright / golangci-lint (+ optional .NET)
│   ├── setup-apm-home.sh      #   APM + my-claude-apm-setup into ~/.claude
│   ├── provision.sh           #   orchestrator (sentinel-guarded, idempotent)
│   └── push-kit.sh            #   publish the kit to an OCI registry
├── docs/credentials.md        # binding Pulumi / cloud creds
├── docs/network.md            # extending the allow-list for your clouds
└── Makefile                   # build / load / push / validate / run / pin
```

## Pinned versions

| Component | Default | Where to change |
|---|---|---|
| Pulumi CLI / ESC | `3.255.0` / `0.26.0` | `scripts/install-pulumi.sh` (+ SHA256s), `kit/spec.yaml`, `Makefile` |
| Terraform | `1.15.8` | `scripts/install-iac.sh`, `kit/spec.yaml`, `Makefile` |
| OpenTofu | `1.12.5` | same |
| AWS CLI v2 | `2.36.10` | `scripts/install-clouds.sh` (+ SHA256s), `kit/spec.yaml`, `Makefile` |
| Azure CLI / gcloud | latest (GPG apt) | vendor repos; az dist pinned via `AZ_APT_DIST` (`noble`) |
| my-claude-apm-setup | `v0.4.0` | `ISK_APM_SETUP_REF` |
| Base image | `docker/sandbox-templates:claude-code-docker` | `BASE` build arg |

`make help` lists every target. Validate with `make validate` (`sbx kit validate ./kit`).

## How this compares

Measured against [ajeetraina's `sbx-kits-*`](https://github.com/ajeetraina?tab=repositories&q=sbx-kits)
collection (Firecrawl, mem0, SurrealDB, Grafana, Dagger, VS Code, and others):

- It is the first IaC kit. Nothing in his `awesome-docker-sbx` catalog covers
  Pulumi, Terraform or OpenTofu; those kits each wrap a single tool.
- Every tool here is installed from a pinned version and verified by SHA256 or a
  GPG signature. The community kits mostly install with `curl | sh` or
  `pip install ==x` (see the table above).
- No other kit wires a whole agent-config framework (skills, subagents, hooks,
  MCP) into `~/.claude`.
- It uses the documented v2 spec surface (`permissions`, `setup`,
  `agentInstructions`) and validates clean against Docker's reference `sbx` spec
  library. Several community `schemaVersion:"2"` kits use canonical keys that the
  strict v2 decoder rejects.
- It also borrows two things from his kits: OCI publishing (`sbx kit push` to
  GHCR, via `.github/workflows/publish-kit.yaml`) and starter runbook files
  (`kit/files/home/runbooks/`).

## Notes and limitations

- Cloud endpoints beyond the starters must be added per provider and region to
  the `permissions.network.allow` list in `kit/spec.yaml`. Sandbox policy enforces
  only exact hosts and single-label `*.host` wildcards. See
  [`docs/network.md`](docs/network.md).
- Cloud auth is not baked in. `aws`, `az` and `gcloud` need credentials at run
  time (env vars) or through Pulumi ESC. AWS uses SigV4, so its credentials stay
  in the container. See [`docs/credentials.md`](docs/credentials.md).
- Kits are experimental. The spec targets `schemaVersion: "2"` and validates
  clean against the current `sbx` spec library.

## License

MIT. See [`LICENSE`](LICENSE).
