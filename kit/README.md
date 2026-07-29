# Infrastructure kit (mixin)

The declarative half of `infrastructure-sandbox-kit`: a `schemaVersion: "2"`,
`kind: mixin` kit that layers the IaC toolchain onto the built-in `claude` agent.
It carries the network allow-list, the Pulumi Cloud credential and the agent
context. When the tools aren't already baked into a [template image](../template),
it also provisions them (Pulumi, Terraform, OpenTofu, the AWS/Azure/gcloud CLIs
and APM) at sandbox-create time.

```bash
# On the stock claude image (zero build, installs at create time):
sbx run --kit "git+https://github.com/dirien/infrastructure-sandbox-kit.git#dir=kit" claude .

# On the baked template (install is a fast no-op; kit just wires net/creds/MCP):
sbx run --template infrastructure-sandbox:latest --kit ../kit claude .

# Validate / inspect:
sbx kit validate ./            # or:  make validate   (from repo root)
sbx kit inspect ./ --output json
```

## What it declares

- `requires.agent: claude`: Claude-specific wiring, so it only composes onto the
  `claude` base agent.
- `permissions.network.allow`: the Pulumi, Terraform and OpenTofu download and
  registry hosts, the AWS/Azure/Google installer and apt hosts, GitHub, the
  language registries (npm, PyPI, Go proxy), the APM installer, the MCP hosts, and
  a cloud control-plane starter set (AWS STS, Azure ARM and login,
  `*.googleapis.com`). Add the rest of your cloud and region endpoints here; see
  [`../docs/network.md`](../docs/network.md).
- `credentials[].pulumi`: injects `PULUMI_ACCESS_TOKEN` as
  `Authorization: token <PAT>` on `api.pulumi.com` through the proxy (sentinel-swap,
  so the container sees only `proxy-managed`). Cloud creds are supplied separately;
  see [`../docs/credentials.md`](../docs/credentials.md).
- `environment.variables`: `PULUMI_SKIP_UPDATE_CHECK`, `AWS_PAGER`,
  `CLOUDSDK_CORE_DISABLE_PROMPTS`.
- `setup.install`: runs once, as the `agent` user, before Claude launches. It finds
  the provisioning scripts (baked image first, otherwise fetched from this repo at
  `KIT_REF`) and runs `provision.sh`, which is a no-op when the tools are already
  provisioned.
- `agentInstructions.content`: IaC guidance, surfaced to Claude through the mixin's
  sbx-generated `kits-memory/infrastructure.md` file.

## Pinning

`setup.install` hardcodes the pins, because a kit's `environment.variables` aren't
set yet when the install hook runs:

- `ISK_PULUMI_VERSION`, `ISK_ESC_VERSION`, `ISK_TERRAFORM_VERSION`,
  `ISK_OPENTOFU_VERSION`, `ISK_AWSCLI_VERSION`, `ISK_INSTALL_CLOUDS`,
  `ISK_APM_SETUP_REF`, `ISK_INSTALL_DOTNET`: edit inline in `spec.yaml`.
- `KIT_REF`: the ref the provisioning scripts are fetched from. It defaults to
  `main`. For reproducible zero-build runs, pin the kit URL (`…#dir=kit&ref=<tag>`)
  and set the matching `KIT_REF` (`make pin REF=<tag>` from the repo root does that).

## Toggles

- Skip the cloud CLIs for a faster create: set `ISK_INSTALL_CLOUDS="0"`.
- Enable .NET (Pulumi C#): uncomment the `.NET` domains under
  `permissions.network.allow` and set `ISK_INSTALL_DOTNET="1"`. On the template
  path, use `make build INSTALL_DOTNET=1` instead.
