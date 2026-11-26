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
- Go, Node.js and Python plus the language servers `gopls`,
  `typescript-language-server`, `pyright` and `golangci-lint`. The template
  image ships the runtimes; on the Debian-based built-in `claude` agent the kit
  adds Go and Node.js from its apt sources. Enabling .NET adds `csharp-ls` and
  the .NET SDK.
- The Pulumi Cloud token, injected by the sandbox credential proxy. The container
  only ever sees `PULUMI_ACCESS_TOKEN=proxy-managed`.
- The `pulumi` MCP server at user scope (registry lookups, schema and code
  validation, Neo).
- The APM setup in `~/.claude` for every workspace: 37 skills (including the
  official Pulumi skills, `terraform-skill` with its `code-intelligence`
  companion, `shellcheck-configuration`, `typescript-expert`, `clarity`, and
  `ai-slop-detector`), 3 subagents, the instruction rules, two guardrail hooks, and the rtk hook. One
  guardrail blocks destructive shell commands; the other scans edits for secrets
  and formats them. The rtk hook compresses command output before the agent
  reads it, except inside Claude Code worktrees (see
  [Notes and limitations](#notes-and-limitations)).
- A colored Claude Code status line (directory, git branch, model, context
  use) from the APM setup, re-applied on every start. On the built-in `claude`
  agent it replaces Docker's default status line and forwards the session data
  to Docker's `sbx-claude-hook`, so the Docker Desktop session view keeps
  working. A `statusLine` you set yourself is left alone.

## Two ways to use it

| | Sandbox kit (one flag) | Mixin on the built-in `claude` agent |
|---|---|---|
| What | One OCI artifact (kit-spec v2) that names the prebuilt template image and carries all the rules | The `kit/` mixin (kit-spec v3) layered onto `sbx run claude`, installed at create time |
| Base | The template image (Ubuntu 26.04, tools baked in) | Docker's `claude` workload (Debian 13, Docker Hardened Images) |
| Speed | Instant sandbox starts | A few minutes on first create (downloads + APM) |
| Needs | nothing (published on GHCR) | nothing (published on GHCR) |

Both apply the same declarations: the network rules, the Pulumi credential, the
MCP servers and the agent instructions. The mixin runs the built-in `claude`
agent, so Claude's own auth is untouched; the sandbox kit defines the agent
itself and pins the image (see [`sandbox-kit/`](sandbox-kit)).

Since sbx 0.51 the built-in `claude` agent is a kit-spec v3 kit, and sbx refuses
to layer v1/v2 mixins onto it, so the mixin is a v3 kit. The older
"template image + mixin" path (`--template … --kit ./kit claude`) is retired:
use the sandbox kit, which runs the same template image.

## Prerequisites

- [`sbx`](https://github.com/docker/sbx-releases) ≥ 0.54.1 and Docker on your
  host. The sandbox CLI is a host tool. Kits are experimental; the v3 mixin
  needs a release whose built-in `claude` agent is a v3 kit (0.51+), and this
  repo is tested against 0.54.1.
- A Pulumi Cloud access token, and whatever cloud credentials your stacks need
  (see [`docs/credentials.md`](docs/credentials.md)).

## Run it

### One artifact: the sandbox kit

```bash
sbx secret set -g pulumi           # one-time: bind your Pulumi token (docs/credentials.md)
sbx run --kit ghcr.io/dirien/infrastructure-sandbox-kit:v0.11.1 infrastructure-sandbox .
```

The kit names the template image and carries every rule. A sandbox kit defines
its own agent, named after the kit, and `sbx run` expects exactly that agent
name (`infrastructure-sandbox`; it still runs Claude Code, since that is what
the image ships). Details in [`sandbox-kit/`](sandbox-kit).

The template image behind it is built by `template/` (`make load` builds it
locally and loads it into sbx; see [`template/`](template)).

### Mixin on the built-in claude agent

The mixin is published to GHCR by the `publish-kit` workflow, and it also runs
straight from git or from a local clone. Pick whichever fits:

```bash
sbx secret set -g pulumi           # one-time: bind your Pulumi token (docs/credentials.md)

# From the published kit on GHCR:
sbx run --kit ghcr.io/dirien/infrastructure-kit:v0.11.1 --skills=off --name "iac-${PWD##*/}" claude .

# Straight from this repo over git:
sbx run --kit "git+https://github.com/dirien/infrastructure-sandbox-kit.git#dir=kit&ref=v0.11.1" --skills=off --name "iac-${PWD##*/}" claude .

# From a local clone (the kit lives under kit/):
git clone https://github.com/dirien/infrastructure-sandbox-kit.git
sbx run --kit ./infrastructure-sandbox-kit/kit --skills=off --name "iac-${PWD##*/}" claude .     # or: make run-kit

# Later, re-attach to the same sandbox (no kit flags):
sbx run --name "iac-${PWD##*/}"
```

Keep both flags:

- `--skills=off`: without it the APM skills don't install (see
  ["What APM in the agent home means here"](#what-apm-in-the-agent-home-means-here) below).
- `--name`: without it, `sbx run` targets the directory's default sandbox,
  `claude-<directory>`. If you ever ran plain `claude` in that directory, that
  sandbox already exists, and sbx 0.54.1 refuses to add a kit to it. The error
  says the kit "resolve[s] only when it is composed with its workload" or that
  "--kit can only be used when creating a new sandbox". A name that isn't taken
  always creates a new sandbox. (`--new` doesn't help here: sbx 0.54.1 supports
  it only with `--cloud`.) `"iac-${PWD##*/}"` (bash/zsh) names it after the
  directory; any unused name works (letters, digits, hyphens, periods). To
  re-create the sandbox, `sbx rm` it first. A kit can only be added when the
  sandbox is created.

The git and local forms are kit sources: sbx builds the v3 kit image in its
kit builder sandbox (`sbx kit builder status`) before it creates the sandbox.

By default `sbx` only allows kits from `docker.io/`. Authorize the GHCR and GitHub
sources once on your host (local `./kit` paths are allowed by default):

```bash
sbx settings set kit.allowedSources '["docker.io/","ghcr.io/dirien/","github.com/dirien/"]'
```

The kit installs the toolchain at create time, which takes a few minutes. Add
`--skills=off` to get the APM skills (see
[What "APM in the agent home" means here](#what-apm-in-the-agent-home-means-here)).

Reproducibility: the kit fetches its provisioning scripts from `KIT_REF` in
`kit/infrastructure.yaml`, which is pinned to an immutable release tag
(`v0.11.1`), not a moving branch — so the scripts don't change under you even if
you fetch the kit from `main`. The published OCI artifact goes further:
`scripts/push-kit.sh` rewrites `KIT_REF` to the exact commit SHA. To pin a git
run to a different release, use `…&ref=<tag>`; `make pin REF=<tag>` sets
`KIT_REF` in both kits.

Once the sandbox is up, `~/runbooks/` holds credential-free Pulumi and
Terraform/OpenTofu starters:

```bash
cd ~/runbooks/terraform-random && terraform init && terraform plan
```

## Install hardening

The core IaC tools are installed from a pinned version and verified by checksum
or signature, no `curl | sh`. That covers Pulumi and ESC, Terraform, OpenTofu,
kubectl and Helm, the AWS CLI (pinned + SHA256), Azure CLI and gcloud (GPG-signed vendor apt
repos), and the APM CLI (pinned release tarball + pinned per-arch SHA256 — apm's
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
| APM CLI | GitHub release tarball | pinned per-arch SHA256 (published SHA256 for an overridden version) |

## What "APM in the agent home" means here

`dirien/my-claude-apm-setup` is normally consumed per repo with `apm install`.
This kit instead materializes it at user scope, so it applies in every workspace
opened in the sandbox without a per-project `apm.yml`:

| Materialized to | From the setup |
|---|---|
| `~/.claude/skills/*` | 37 skills (32 pinned deps + 5 local) and the `apm-lsp` LSP plugin |
| `~/.claude/agents/*` | `executor`, `librarian`, `reviewer` subagents |
| `~/.claude/rules/*` + a managed block in `~/.claude/CLAUDE.md` | the instruction rules |
| `~/.claude/settings.json` | the guard and rtk hooks (PreToolUse) and the secret-scan/format hook (PostToolUse), rewritten to absolute paths so they fire in any workspace |
| `~/.claude.json` (user scope) | the `pulumi` MCP server |

`~/.claude/skills` is not always a plain directory. `sbx` wires its shared
skills store there (`--skills=readonly` is the default). On sbx 0.54.1 the
built-in `claude` agent gets the store as a read-only mount, even when the store
is empty, and the kit cannot write into it. Provisioning then skips the skills
and the `apm-lsp` plugin with a warning. The toolchain, agents, rules, hooks and
MCP still install, and the managed `CLAUDE.md` block records that the skills are
missing. Where sbx instead links store skills into a writable directory, the kit
copies its skills beside them and keeps the store's copy of any name both carry.
That is why every mixin command in this README passes `--skills=off`: the kit
then gets its own skills directory.

`--skills=readwrite` also works, but the kit then writes its skills into the
shared store, where they outlive the sandbox and appear in unrelated ones.

The built-in `claude` agent rewrites `~/.claude/settings.json` and
`~/.claude.json` when it creates a sandbox, adding Docker's `sbx-claude-hook`
hooks, its status line and the MCP gateway. The kit's install step runs after
that, and `apply-agent-config.sh` writes the APM hooks, status line and MCP
server back on every start. Docker's hooks stay next to them. Before it does,
it removes any hook that came from the setup but isn't in the current version,
so a renamed or replaced hook doesn't keep running next to the new one. It
treats a hook as the setup's when its command points into
`~/.claude-apm-setup` or is a bare `rtk hook claude`. Hooks you add yourself
are kept.

To update it later, run `git -C ~/.claude-apm-setup pull && ISK_FORCE=1 ~/.local/share/infrastructure-sandbox-kit/scripts/provision.sh`.

## Layout

```
infrastructure-sandbox-kit/
├── kit/infrastructure.yaml    # the mixin: kit-spec v3 descriptor (kind: mixin, requires claude)
├── kit/infrastructure.dockerfile  # its overlay: the runbooks under /opt/infrastructure-sandbox-kit
├── kit/files/home/runbooks/   # credential-free Pulumi + Terraform starters (shared by both kits)
├── sandbox-kit/spec.yaml      # the one-flag bundle: kit-spec v2 kind: sandbox, pins the image + same rules
├── template/Dockerfile        # the baked image (FROM claude-code-docker)
├── scripts/                   # canonical provisioning, shared by both paths
│   ├── lib.sh                 #   shared helpers (arch, fetch, verify)
│   ├── install-pulumi.sh      #   Pulumi CLI (pinned, SHA256-verified)
│   ├── install-iac.sh         #   Terraform + OpenTofu (SHA256SUMS-verified)
│   ├── install-clouds.sh      #   AWS (pinned SHA) + Azure/gcloud (GPG apt), per-component
│   ├── install-toolchains.sh  #   gopls / tsserver / pyright / golangci-lint (+ optional .NET)
│   ├── setup-apm-home.sh      #   APM + my-claude-apm-setup into ~/.claude
│   ├── apply-agent-config.sh  #   (re)apply hooks + status line + MCP, drop stale setup hooks (idempotent)
│   ├── provision.sh           #   orchestrator (sentinel-guarded, idempotent)
│   ├── startup.sh             #   setup.startup: re-apply config + retry missing clouds
│   └── push-kit.sh            #   publish a kit to an OCI registry (v3: buildx, v2: sbx kit push)
├── docs/credentials.md        # binding Pulumi / cloud creds
├── docs/network.md            # extending the allow-list for your clouds
└── Makefile                   # build / load / push / validate / run / pin
```

## Pinned versions

| Component | Default | Where to change |
|---|---|---|
| Pulumi CLI | `3.273.0` | `scripts/install-pulumi.sh` (+ SHA256s), `kit/infrastructure.yaml`, `sandbox-kit/spec.yaml`, `Makefile` |
| Terraform | `1.17.1` | `scripts/install-iac.sh`, `kit/infrastructure.yaml`, `sandbox-kit/spec.yaml`, `Makefile` |
| OpenTofu | `1.13.2` | same |
| kubectl | `1.37.2` | same |
| Helm | `4.3.1` | same |
| AWS CLI v2 | `2.39.3` | `scripts/install-clouds.sh` (+ SHA256s), `kit/infrastructure.yaml`, `sandbox-kit/spec.yaml`, `Makefile` |
| Azure CLI / gcloud | latest (GPG apt) | vendor repos; the az dist follows the OS codename (`resolute` on the template, `bookworm` on Debian 13 trixie, which Microsoft doesn't publish yet); override with `ISK_AZ_APT_DIST` |
| Go / Node.js (mixin only) | `golang-1.26`, `nodejs-24` + `npm` | DHI apt packages, installed only when missing; `ISK_GO_APT_PACKAGE`, `ISK_NODE_APT_PACKAGE` |
| my-claude-apm-setup | `v0.7.0` | `ISK_APM_SETUP_REF` |
| APM CLI | `0.39.0` | `ISK_APM_VERSION` (pinned per-arch SHA256s in `scripts/setup-apm-home.sh`; bump deliberately) |
| sbx (CI) | `v0.54.1` | `SBX_RELEASE` in `.github/workflows/publish-kit.yaml` and `validate-kits.yaml` |
| Template base image | `docker/sandbox-templates:claude-code-docker` | `BASE` build arg |
| Mixin base | the built-in `claude` agent (`docker.io/sbx/claude`, Debian 13) | chosen by sbx |

`make help` lists every target. `make validate` validates both kits: the v3
mixin with `sbx kit validate ./kit` (sbx builds it in its kit builder, so the
daemon must be running) and the sandbox kit with `sbx kit validate --offline`.
`make build-kit` builds the v3 mixin with `docker buildx`, which is what CI
runs.

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
- It borrows two things from his kits: OCI publishing to GHCR (via
  `.github/workflows/publish-kit.yaml`) and starter runbook files
  (`kit/files/home/runbooks/`).

## Notes and limitations

- Cloud endpoints beyond the starters must be added per provider and region to
  the network allow list: the `network-policy@1` capability in
  `kit/infrastructure.yaml` (both its `install` and `runtime` lists) and
  `permissions.network.allow` in `sandbox-kit/spec.yaml`. On the host,
  `sbx policy check network <host>` shows whether a host is allowed. See
  [`docs/network.md`](docs/network.md).
- Cloud auth is not baked in. `aws`, `az` and `gcloud` need credentials supplied
  at run time or through Pulumi ESC. AWS uses SigV4, so its credentials stay in
  the container. See [`docs/credentials.md`](docs/credentials.md).
- Kits are experimental. The mixin uses the kit-spec v3 grammar
  ([docker/sandbox-kit-spec](https://github.com/docker/sandbox-kit-spec)): a
  `# syntax=docker/sandbox-kit:3` descriptor whose behavior is a list of typed
  capabilities (`network-policy@1`, `credential@1`, `lifecycle@1`,
  `agent-context@2`), published as an OCI image built by that BuildKit
  frontend. The sandbox kit stays on the v2 grammar
  ([kit reference](https://docs.docker.com/ai/sandboxes/customize/kit-reference/)),
  which sbx still runs as a standalone agent. `sbx kit validate --offline`
  (sbx 0.49.1+) checks the v2 kit without a daemon or sign-in; it refuses v3
  source kits, which need the kit builder.
- v3 lifecycle hooks see only the environment variables they declare, and the
  install hook runs before Claude starts. Pins therefore live inline in the
  install hook; `PULUMI_SKIP_UPDATE_CHECK`, `AWS_PAGER` and
  `CLOUDSDK_CORE_DISABLE_PROMPTS` are kit args exported to the container, so
  `--kit-arg` can override them.
- The rtk hook from the APM setup doesn't rewrite commands inside Claude Code
  worktrees (`.claude/worktrees/`, used by `claude --worktree` and worktree
  subagents). Claude Code refuses git in an isolated worktree when a launcher
  wraps it, so `rtk git status` would fail there
  ([rtk-ai/rtk#3864](https://github.com/rtk-ai/rtk/issues/3864)). Command
  output in those sessions is uncompressed. Don't run `rtk init -g` in the
  sandbox: it registers a bare `rtk hook claude`, which rewrites in worktrees
  again until the next sandbox start removes it.

## License

MIT. See [`LICENSE`](LICENSE).
