# Pulumi kit (mixin)

The declarative half of `pulumi-sandbox-kit`: a `schemaVersion: "2"`,
`kind: mixin` kit that layers Pulumi onto the built-in `claude` agent. It carries
the Pulumi network allow-list, the Pulumi Cloud credential, the agent context —
and, when the tools aren't already baked into a [template image](../template), it
provisions them at sandbox-create time.

```bash
# On the stock claude image (zero build — installs at create time):
sbx run --kit "git+https://github.com/dirien/pulumi-sandbox-kit.git#dir=kit" claude .

# On the baked template (install is a fast no-op; kit just wires net/creds/MCP):
sbx run --template pulumi-sandbox:latest --kit ../kit claude .

# Validate / inspect:
sbx kit validate ./            # or:  make validate   (from repo root)
sbx kit inspect ./ --output json
```

## What it declares

- **`requires.agent: claude`** — Claude-specific wiring, so it only composes onto
  the `claude` base agent.
- **`permissions.network.allow`** — Pulumi service + plugin hosts, GitHub,
  language registries (npm/PyPI/Go proxy), the APM installer, and the MCP hosts.
  **Add your cloud provider domains here** — see [`../docs/network.md`](../docs/network.md).
- **`credentials[].pulumi`** — injects `PULUMI_ACCESS_TOKEN` as
  `Authorization: token <PAT>` on `api.pulumi.com` via the proxy (sentinel-swap;
  the container sees only `proxy-managed`). Bind it per
  [`../docs/credentials.md`](../docs/credentials.md).
- **`environment.variables`** — `PULUMI_SKIP_UPDATE_CHECK=true`.
- **`setup.install`** — runs once, as the `agent` user, before Claude launches.
  It locates the provisioning scripts (baked image first, otherwise fetched from
  this repo at `KIT_REF`) and runs `provision.sh`, which is a no-op when the image
  already provisioned.
- **`agentInstructions.content`** — Pulumi guidance, surfaced to Claude via the
  mixin's `kits-memory/pulumi.md` progressive-disclosure file.

## Pinning

`setup.install` hardcodes the pins (a kit's `environment.variables` aren't set yet
when the install hook runs, so they can't be used here):

- `PSK_PULUMI_VERSION`, `PSK_ESC_VERSION`, `PSK_APM_SETUP_REF`,
  `PSK_INSTALL_DOTNET` — edit inline in `spec.yaml`.
- `KIT_REF` — the ref the provisioning scripts are fetched from. Defaults to
  `main`. For reproducible zero-build runs, pin the kit URL
  (`…#dir=kit&ref=<tag>`) **and** set the matching `KIT_REF`
  (`make pin REF=<tag>` from the repo root does the latter).

## Enabling .NET

Uncomment the `.NET` domains under `permissions.network.allow` and set
`PSK_INSTALL_DOTNET="1"` in `setup.install`. On the template path, build with
`make build INSTALL_DOTNET=1` instead.
