# Infrastructure kit (v3 mixin)

The declarative half of `infrastructure-sandbox-kit`: a kit-spec v3
`kind: mixin` that layers the IaC toolchain onto the built-in `claude` agent
(`requires: [claude]`; needs `sbx` 0.51 or later, where `claude` itself is a v3
kit, and is tested on 0.54.1). It carries the network allow list, the Pulumi
Cloud credential, the environment defaults and the agent instructions, and it
provisions Pulumi, Terraform, OpenTofu, kubectl, Helm, the AWS/Azure/gcloud
CLIs, Go/Node.js language servers and APM at sandbox-create time. If you would
rather pass one flag that bundles a prebuilt image with these same
declarations, use the [`../sandbox-kit`](../sandbox-kit) variant.

```bash
# From GHCR, git, or this directory (sbx builds git and local kits in its kit builder).
# --skills=off gives the kit its own skills directory; without it the APM skills
# don't install, because sbx mounts its shared skills store read-only.
# --name picks a sandbox that doesn't exist yet; without it sbx targets the
# directory's default claude-<dir> sandbox and refuses the kit if that one
# already exists (see the repo README).
sbx run --kit ghcr.io/dirien/infrastructure-kit:v0.11.0 --skills=off --name "iac-${PWD##*/}" claude .
sbx run --kit "git+https://github.com/dirien/infrastructure-sandbox-kit.git#dir=kit&ref=v0.11.0" --skills=off --name "iac-${PWD##*/}" claude .
sbx run --kit ./ --skills=off --name "iac-${PWD##*/}" claude .     # or: make run-kit   (from repo root)
sbx run --name "iac-${PWD##*/}"           # re-attach later, without kit flags

# Validate / build / inspect:
sbx kit validate ./                        # or: make validate   (needs the sbx daemon)
make build-kit                             # docker buildx, what CI runs
sbx kit inspect ./ --json
```

Remote sources (GHCR, git) need one-time authorization, since `sbx` allows only
`docker.io/` by default:

```bash
sbx settings set kit.allowedSources '["docker.io/","ghcr.io/dirien/","github.com/dirien/"]'
```

## Files

- `infrastructure.yaml`: the descriptor. Its first line,
  `# syntax=docker/sandbox-kit:3`, selects the BuildKit frontend that builds and
  validates the kit.
- `infrastructure.dockerfile`: the overlay the kit adds to the workload image.
  It carries only the runbooks, at `/opt/infrastructure-sandbox-kit/runbooks`;
  the install hook seeds them into `~/runbooks`. The toolchain installs at
  create time, so it follows the workload's OS and architecture.
- `files/home/runbooks/`: the runbooks themselves, shared with the sandbox kit.

## What it declares

- `requires: [claude]`: the APM setup and hooks are Claude-specific, so the kit
  only composes with a workload that provides `claude`.
- `args`: `PULUMI_SKIP_UPDATE_CHECK`, `AWS_PAGER` and
  `CLOUDSDK_CORE_DISABLE_PROMPTS`, exported into the container. Override with
  `--kit-arg pulumiSkipUpdateCheck=false` and so on.
- `network-policy@1`: the same allow list for the `install` phase (provisioning)
  and the `runtime` phase (the agent, and `startup.sh` retrying cloud CLIs): the
  Pulumi, Terraform/OpenTofu and kubectl/Helm download and registry hosts, the
  AWS/Azure/Google installer and apt hosts, the workload's Debian and Docker
  Hardened Images apt sources (`deb.debian.org`, `dhi.io`), GitHub (which also
  serves the APM CLI releases and this kit's scripts), the language registries
  (npm, PyPI, Go proxy), the MCP hosts, and a cloud control-plane starter set
  (AWS STS, Azure ARM and login, `*.googleapis.com`). Add the rest of your cloud
  and region endpoints to both lists; see [`../docs/network.md`](../docs/network.md).
- `credential@1`: the Pulumi token, service `pulumi`, runtime phase, with a
  proxy-managed `apiKey` that injects `Authorization: token <PAT>` on
  `api.pulumi.com`. The container sees only `PULUMI_ACCESS_TOKEN=proxy-managed`.
  Store the token with
  `printf '%s\n' "$PULUMI_ACCESS_TOKEN" | sbx secret set -g pulumi`. It is
  optional: without a binding the kit runs and `pulumi` is simply logged out.
  Cloud creds are supplied separately; see [`../docs/credentials.md`](../docs/credentials.md).
- `lifecycle@1` `install`: runs once at create, as the `agent` user, after the
  `claude` workload's own install hooks. It fetches the provisioning scripts
  from this repo at `KIT_REF` into
  `~/.local/share/infrastructure-sandbox-kit/scripts`, seeds `~/runbooks`, and
  runs `provision.sh`. v3 hooks see only the environment variables they
  declare, so it lists the proxy and CA variables the downloads need.
- `lifecycle@1` `startup`: runs `startup.sh` on every start. The `claude`
  workload rewrites `~/.claude/settings.json` and `~/.claude.json` when it
  creates a sandbox, so this re-applies the APM guardrail hooks, status line and
  MCP servers (via `apply-agent-config.sh`), and retries any cloud CLI that
  didn't install at create time. Both are idempotent.
- `agent-context@2`: the IaC guidance surfaced to Claude (sbx 0.51+). The kit
  declares one version only: sbx can't resolve a mixin that offers competing
  agent-context versions on its own, which breaks `sbx run` against an
  existing sandbox with a misleading error.

Cloud CLI installs are per-component and non-fatal: a flaky Azure/Google apt repo
never blocks `sbx create`. The sandbox comes up, and `startup.sh` fills in the
missing CLI on a later start (tracked by version/presence). Core tools (Pulumi,
Terraform, OpenTofu) are still fatal.

## Pinning

The install hook hardcodes the pins:

- `ISK_PULUMI_VERSION`, `ISK_TERRAFORM_VERSION`, `ISK_OPENTOFU_VERSION`,
  `ISK_KUBECTL_VERSION`, `ISK_HELM_VERSION`, `ISK_AWSCLI_VERSION`,
  `ISK_INSTALL_CLOUDS`, `ISK_APM_SETUP_REF`, `ISK_APM_VERSION`,
  `ISK_INSTALL_DOTNET`: edit inline in `infrastructure.yaml`. The apm CLI is
  pinned and SHA256-verified like the other core tools; bump `ISK_APM_VERSION`
  deliberately and together with `ISK_APM_SETUP_REF` (my-claude-apm-setup v0.7.0
  needs apm 0.39.0 for its v4 lockfile).
- `ISK_AZ_APT_DIST`: empty derives the Microsoft azure-cli repo dist from
  `/etc/os-release` (Debian 13 trixie uses `bookworm`).
- `KIT_REF`: the ref the provisioning scripts are fetched from, pinned to a
  release tag. The published OCI artifact pins it to the exact commit SHA. For
  a git run at another release, use `…#dir=kit&ref=<tag>` and set the matching
  `KIT_REF` (`make pin REF=<tag>` from the repo root does that).

## Toggles

- Skip the cloud CLIs for a faster create: set `ISK_INSTALL_CLOUDS="0"`.
- Enable .NET (Pulumi C#): uncomment the `.NET` hosts in the network policy and
  set `ISK_INSTALL_DOTNET="1"`.
