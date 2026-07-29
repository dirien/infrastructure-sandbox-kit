# infrastructure-sandbox-kit

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) template **and** kit
that turns a Claude Code sandbox into a ready-to-go **Infrastructure-as-Code**
workstation — Pulumi, Terraform, OpenTofu and the AWS/Azure/GCP CLIs — with
[`dirien/my-claude-apm-setup`](https://github.com/dirien/my-claude-apm-setup)
(APM) wired into the agent home out of the box.

You get, the moment the sandbox starts:

- **Pulumi CLI + ESC**, **Terraform**, **OpenTofu** — all pinned and
  checksum/signature-verified, with Pulumi's bundled language plugins.
- **Cloud CLIs**: **AWS CLI v2**, **Azure CLI**, **gcloud** (skippable with
  `INSTALL_CLOUDS=0`).
- **Language toolchain** from the base image (Go, Node, Python, Java) plus
  language servers — `gopls`, `typescript-language-server`, `pyright`,
  `golangci-lint` (and `csharp-ls` + the .NET SDK when you enable .NET).
- **The Pulumi Cloud token** injected through the sandbox credential proxy — the
  container only ever sees `PULUMI_ACCESS_TOKEN=proxy-managed`.
- **MCP servers** at user scope: `pulumi` (registry / schema / code validation /
  Neo) and `context7` (up-to-date library docs).
- **APM: `dirien/my-claude-apm-setup`** materialized into `~/.claude` globally —
  23 skills, 3 subagents, the instruction rules, and the two guardrail hooks
  (destructive-command guard + secret-scan/format on edit), plus its MCP servers.

## Two ways to use it

| | **Template** (recommended) | **Zero-build kit** (interim) |
|---|---|---|
| What | A prebuilt image with everything baked in | The stock `claude` image + this kit, installed at create time |
| Speed | Instant sandbox starts | A few minutes on first create (downloads + APM) |
| Command | `make load && make run` | `sbx run --kit "git+…#dir=kit" claude .` |
| Needs | one image build | the repo pushed to GitHub (scripts are fetched at create time) |

Both run the **built-in `claude` agent** (so Claude's own auth is untouched) and
apply the same `kit/` mixin for the network rules, Pulumi credential, MCP and
agent context.

## Prerequisites

- [`sbx`](https://github.com/docker/sbx-releases) and Docker on your host (the
  sandbox CLI is a host tool). Kits are experimental — keep `sbx` current.
- A Pulumi Cloud access token, and whatever cloud credentials your stacks need
  (see [`docs/credentials.md`](docs/credentials.md)).

## Quickstart — template (recommended)

```bash
make load                          # docker build + sbx template load
#   leaner (no cloud CLIs):  make load INSTALL_CLOUDS=0
#   add .NET (Pulumi C#):    make load INSTALL_DOTNET=1

sbx secret set -g pulumi           # one-time: bind your Pulumi token (see docs/credentials.md)

make run                           # sbx run --template infrastructure-sandbox:latest --kit ./kit claude .
```

Prefer a registry? `make build push IMAGE=ghcr.io/dirien/infrastructure-sandbox:v1`,
then `sbx run --template ghcr.io/dirien/infrastructure-sandbox:v1 --kit ./kit claude .`.

## Quickstart — zero-build kit (interim)

Works on the stock `claude` sandbox with no image build. Because a kit's install
hook runs *before* its files are placed, the provisioning scripts are fetched
from this repo at create time — so **push the repo first** (or point the URL at
your fork):

```bash
sbx run --kit "git+https://github.com/dirien/infrastructure-sandbox-kit.git#dir=kit" claude .
# pin it:  …#dir=kit&ref=v0.2.0   (and run `make pin REF=v0.2.0` so the fetched scripts match)
```

## Install hardening

Every tool is installed from a pinned version and verified — no `curl | sh`
pipes. This was the main gap in the comparable community kits (see
[How this compares](#how-this-compares)).

| Tool | Method | Verification |
|---|---|---|
| Pulumi CLI + ESC | GitHub release tarball | pinned per-arch **SHA256** |
| Terraform | HashiCorp releases | published **SHA256SUMS** |
| OpenTofu | GitHub release | published **SHA256SUMS** |
| AWS CLI v2 | official installer zip | pinned per-arch **SHA256** |
| Azure CLI | Microsoft apt repo | **GPG-signed** (apt) |
| gcloud | Google Cloud apt repo | **GPG-signed** (apt) |

## What "APM in the agent home" means here

`dirien/my-claude-apm-setup` is normally consumed per-repo via `apm install`.
This kit instead materializes it at **user scope** so it applies in *every*
workspace opened in the sandbox — no per-project `apm.yml` required:

| Materialized to | From the setup |
|---|---|
| `~/.claude/skills/*` | 23 pinned skills |
| `~/.claude/agents/*` | `executor`, `librarian`, `reviewer` subagents |
| `~/.claude/rules/*` + a managed block in `~/.claude/CLAUDE.md` | the instruction rules |
| `~/.claude/settings.json` | the PreToolUse guard + PostToolUse secret-scan/format hooks — **rewritten to absolute paths** so they fire in any workspace |
| `~/.claude.json` (user scope) | the `context7` and `pulumi` MCP servers |

Update it any time with `git -C ~/.claude-apm-setup pull && ISK_FORCE=1 ~/.local/share/infrastructure-sandbox-kit/scripts/provision.sh`.

## Layout

```
infrastructure-sandbox-kit/
├── kit/spec.yaml              # the kit: kind: mixin (schemaVersion "2"), requires claude
├── template/Dockerfile        # the baked image (FROM claude-code-docker)
├── scripts/                   # canonical provisioning — shared by BOTH paths
│   ├── lib.sh                 #   shared helpers (arch, fetch, verify)
│   ├── install-pulumi.sh      #   Pulumi CLI + ESC (pinned, SHA256-verified)
│   ├── install-iac.sh         #   Terraform + OpenTofu (SHA256SUMS-verified)
│   ├── install-clouds.sh      #   AWS (pinned SHA) + Azure/gcloud (GPG apt)
│   ├── install-toolchains.sh  #   gopls / tsserver / pyright / golangci-lint (+ optional .NET)
│   ├── setup-apm-home.sh      #   APM + my-claude-apm-setup -> ~/.claude (the headline)
│   └── provision.sh           #   orchestrator (sentinel-guarded, idempotent)
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

Benchmarked against [ajeetraina's `sbx-kits-*`](https://github.com/ajeetraina?tab=repositories&q=sbx-kits)
collection (Firecrawl, mem0, SurrealDB, Grafana, Dagger, VS Code, …):

- **First IaC kit** — there is no Pulumi/Terraform/OpenTofu kit anywhere in his
  `awesome-docker-sbx` catalog; those are all single-tool mixins.
- **Install hardening** — the community kits install via `curl | sh` / `pip
  install ==x`; this kit uses pinned **SHA256 / GPG-verified** downloads for every
  tool (table above).
- **APM in the agent home** — no other kit wires a whole agent-config framework
  (skills/subagents/hooks/MCP) into `~/.claude`.
- **Documented v2 grammar** — this kit uses the `permissions`/`setup`/
  `agentInstructions` v2 surface and validates clean against Docker's reference
  `sbx` spec library; several community `schemaVersion:"2"` kits use canonical
  keys the strict v2 decoder rejects.
- **To adopt from him:** OCI publishing (`sbx kit push` + CI) and starter runbook
  files — both are on the roadmap.

## Notes & limitations

- **Cloud endpoints** beyond the starters must be added per provider/region to
  `kit/spec.yaml`'s `permissions.network.allow` — sandbox policy enforces only
  exact hosts and single-label `*.host` wildcards. See [`docs/network.md`](docs/network.md).
- **Cloud auth** isn't baked in: `aws`/`az`/`gcloud` need creds at run time (env)
  or via Pulumi **ESC**; AWS SigV4 keeps credentials container-resident. See
  [`docs/credentials.md`](docs/credentials.md).
- Kits are experimental; the spec targets `schemaVersion: "2"` and validates
  clean against the current `sbx` spec library.

## License

MIT — see [`LICENSE`](LICENSE).
