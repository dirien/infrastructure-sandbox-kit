# pulumi-sandbox-kit

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) template **and** kit
that turns a Claude Code sandbox into a ready-to-go **Pulumi** workstation — with
[`dirien/my-claude-apm-setup`](https://github.com/dirien/my-claude-apm-setup)
(APM) wired into the agent home out of the box.

You get, the moment the sandbox starts:

- **Pulumi CLI + ESC**, checksum-pinned, with all bundled language plugins
  (Go, Node, Python, Java, .NET, YAML).
- **Language toolchain** already in the base image (Go, Node, Python, Java) plus
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
apply the same `kit/` mixin for the Pulumi network rules, credential, MCP and
agent context.

## Prerequisites

- [`sbx`](https://github.com/docker/sbx-releases) and Docker on your host (the
  sandbox CLI is a host tool). Kits are experimental — keep `sbx` current.
- A Pulumi Cloud access token, and whatever cloud credentials your stacks need
  (see [`docs/credentials.md`](docs/credentials.md)).

## Quickstart — template (recommended)

```bash
# 1. Build the image and load it into sbx's local template store (no registry).
make load                          # docker build + sbx template load
#    add .NET (Pulumi C#) too:  make load INSTALL_DOTNET=1

# 2. One-time: tell sbx where your Pulumi token lives (see docs/credentials.md).
sbx secret set -g pulumi "$PULUMI_ACCESS_TOKEN"

# 3. Run Claude on the baked image + the Pulumi kit, in the current repo.
make run                           # sbx run --template pulumi-sandbox:latest --kit ./kit claude .
```

Prefer a registry over the local store? `make build push IMAGE=ghcr.io/dirien/pulumi-sandbox:v1`,
then `sbx run --template ghcr.io/dirien/pulumi-sandbox:v1 --kit ./kit claude .`.

## Quickstart — zero-build kit (interim)

Works on the stock `claude` sandbox with no image build. Because a kit's install
hook runs *before* its files are placed, the provisioning scripts are fetched
from this repo at create time — so **push the repo first** (or point the URL at
your fork):

```bash
sbx run --kit "git+https://github.com/dirien/pulumi-sandbox-kit.git#dir=kit" claude .
# pin it:  …#dir=kit&ref=v0.1.0   (and run `make pin REF=v0.1.0` so the fetched scripts match)
```

First start installs Pulumi + toolchains + APM (a few minutes); the container is
otherwise identical to the template path.

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

The setup repo itself is cloned to `~/.claude-apm-setup` (pinned to
`PSK_APM_SETUP_REF`, default `v0.4.0`) and materialized with `apm install
--frozen`; the wiring script mirrors it into `~/.claude`. Update it any time with
`git -C ~/.claude-apm-setup pull && PSK_FORCE=1 ~/.local/share/pulumi-sandbox-kit/scripts/provision.sh`.

## Layout

```
pulumi-sandbox-kit/
├── kit/spec.yaml              # the kit: kind: mixin (schemaVersion "2"), requires claude
├── template/Dockerfile        # the "perfect template" image (FROM claude-code-docker)
├── scripts/                   # canonical provisioning — shared by BOTH paths
│   ├── lib.sh                 #   shared helpers
│   ├── install-pulumi.sh      #   Pulumi CLI + ESC (pinned, checksum-verified)
│   ├── install-toolchains.sh  #   gopls / tsserver / pyright / golangci-lint (+ optional .NET)
│   ├── setup-apm-home.sh      #   APM + my-claude-apm-setup -> ~/.claude (the headline)
│   └── provision.sh           #   orchestrator (sentinel-guarded, idempotent)
├── docs/credentials.md        # binding Pulumi / Anthropic / cloud creds
├── docs/network.md            # extending the allow-list for your clouds
└── Makefile                   # build / load / push / validate / run / pin
```

The template `Dockerfile` COPYs `scripts/` and runs `provision.sh` at build time;
the zero-build kit fetches the same `scripts/` and runs the same `provision.sh` at
create time. One source of truth, two delivery mechanisms.

## Pinned versions

| Component | Default | Where to change |
|---|---|---|
| Pulumi CLI | `3.255.0` | `scripts/install-pulumi.sh` (+ the two SHA256s), `kit/spec.yaml`, `Makefile` |
| Pulumi ESC | `0.26.0` | same |
| my-claude-apm-setup | `v0.4.0` | `PSK_APM_SETUP_REF` in `kit/spec.yaml` / `Makefile` |
| Base image | `docker/sandbox-templates:claude-code-docker` | `BASE` arg in `template/Dockerfile` |
| .NET SDK | off (`8.0` when enabled) | `INSTALL_DOTNET` / `DOTNET_CHANNEL` |

`make help` lists every target. Validate the kit with `make validate`
(`sbx kit validate ./kit`).

## Notes & limitations

- **Cloud endpoints** must be added to `kit/spec.yaml`'s
  `permissions.network.allow` per provider — sandbox network policy enforces only
  exact hosts and single-label `*.host` wildcards today. See
  [`docs/network.md`](docs/network.md).
- **AWS** auth is SigV4, so its credentials are container-resident (not
  proxy-swapped) and bounded by the allow-list; the simplest path for cloud creds
  is Pulumi **ESC** (`esc` is installed). See [`docs/credentials.md`](docs/credentials.md).
- Kits are experimental; the spec here targets `schemaVersion: "2"` and validates
  clean against the current `sbx` spec library.

## License

MIT — see [`LICENSE`](LICENSE).
