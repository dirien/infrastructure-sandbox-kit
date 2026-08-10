# Infrastructure kit (mixin)

The declarative half of `infrastructure-sandbox-kit`: a `schemaVersion: "2"`,
`kind: mixin` kit that layers the IaC toolchain onto the built-in `claude` agent
(pinned via `requires.agent`; needs `sbx` ≥ 0.38.0, where kit-spec v2 landed).
It carries the network allow-list, the Pulumi Cloud credential and the agent
instructions. When the tools aren't already baked into a [template image](../template),
it also provisions them (Pulumi, Terraform, OpenTofu, the AWS/Azure/gcloud CLIs
and APM) at sandbox-create time.

```bash
# On the stock claude image (zero build, installs at create time):
sbx run --kit "git+https://github.com/dirien/infrastructure-sandbox-kit.git#dir=kit" claude .

# On the baked template (install is a fast no-op; kit just wires net/creds/MCP):
sbx run --template infrastructure-sandbox:v0.6.0 --kit . claude .

# Validate / inspect:
sbx kit validate ./            # or:  make validate   (from repo root)
sbx kit inspect ./ --json
```

Remote sources (GHCR, git) need one-time authorization, since `sbx` allows only
`docker.io/` by default:

```bash
sbx settings set kit.allowedSources '["docker.io/","ghcr.io/dirien/","github.com/dirien/"]'
```

## What it declares

- `requires.agent: claude`: the mixin pins the base agent it layers onto — the
  APM setup and hooks are Claude-specific.
- `permissions.network.allow`: the Pulumi, Terraform and OpenTofu download and
  registry hosts, the AWS/Azure/Google installer and apt hosts, GitHub, the
  language registries (npm, PyPI, Go proxy), the APM installer, the MCP hosts, and
  a cloud control-plane starter set (AWS STS, Azure ARM and login,
  `*.googleapis.com`). Add the rest of your cloud and region endpoints here; see
  [`../docs/network.md`](../docs/network.md).
- `credentials`: the Pulumi token, declared as service `pulumi` with a
  proxy-managed `apiKey` that injects `Authorization: token <PAT>` on
  `api.pulumi.com`; the container sees only the proxy-managed placeholder in
  `PULUMI_ACCESS_TOKEN`. (One block now — in v1 this took `network.serviceDomains`,
  `network.serviceAuth`, `credentials.sources` and `environment.proxyManaged`.)
  Store the token with
  `printf '%s\n' "$PULUMI_ACCESS_TOKEN" | sbx secret set -g pulumi`. Cloud creds
  are supplied separately; see [`../docs/credentials.md`](../docs/credentials.md).
- `environment.variables`: `PULUMI_SKIP_UPDATE_CHECK`, `AWS_PAGER`,
  `CLOUDSDK_CORE_DISABLE_PROMPTS`.
- `setup.install`: runs once, as the `agent` user, before Claude launches. It
  finds the provisioning scripts (baked image first, otherwise fetched from this
  repo at `KIT_REF` into a stable home path) and runs `provision.sh`, a no-op when
  the tools are already provisioned.
- `setup.startup`: runs `startup.sh` on every sandbox start (argv form — v2
  startup commands are not shell-interpreted). Docker reseeds
  Claude's `~/.claude/settings.json` and `~/.claude.json` at create time, so it
  re-applies the APM guardrail hooks and MCP servers (via `apply-agent-config.sh`),
  and retries any cloud CLI that didn't install at create time. Both are idempotent.
- `agentInstructions`: IaC guidance surfaced to Claude (v1's `agentContext`); for
  a mixin it lands in `kits-memory/infrastructure.md` next to the agent profile.

Cloud CLI installs are per-component and non-fatal: a flaky Azure/Google apt repo
never blocks `sbx create`. The sandbox comes up, and `startup.sh` fills in the
missing CLI on a later start (tracked by version/presence). Core tools (Pulumi,
Terraform, OpenTofu) are still fatal.

## Pinning

`setup.install` hardcodes the pins, because a kit's `environment.variables`
aren't set yet when the install hook runs:

- `ISK_PULUMI_VERSION`, `ISK_TERRAFORM_VERSION`,
  `ISK_OPENTOFU_VERSION`, `ISK_AWSCLI_VERSION`, `ISK_INSTALL_CLOUDS`,
  `ISK_APM_SETUP_REF`, `ISK_INSTALL_DOTNET`: edit inline in `spec.yaml`.
- `KIT_REF`: the ref the provisioning scripts are fetched from. It defaults to
  `main`. For reproducible zero-build runs, pin the kit URL (`…#dir=kit&ref=<tag>`)
  and set the matching `KIT_REF` (`make pin REF=<tag>` from the repo root does that).

## Toggles

- Skip the cloud CLIs for a faster create: set `ISK_INSTALL_CLOUDS="0"`.
- Enable .NET (Pulumi C#): uncomment the `.NET` domains under
  `permissions.network.allow` and set `ISK_INSTALL_DOTNET="1"`. On the template path,
  use `make build INSTALL_DOTNET=1` instead.
