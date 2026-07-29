# Network allow-list

Docker Sandboxes egress is default-deny: only hosts in the kit's
`permissions.network.allow` (composed with the base agent's) are reachable. This
kit ships the hosts its own provisioning and the core IaC flow need — **you add
the extra cloud/region endpoints and provider plugins you use.**

## What the kit already allows

| Group | Hosts | Why |
|---|---|---|
| Pulumi | `api.pulumi.com`, `get.pulumi.com`, `mcp.ai.pulumi.com` | state/API, plugin/CLI downloads, hosted MCP |
| Terraform / OpenTofu | `releases.hashicorp.com`, `registry.terraform.io`, `registry.opentofu.org`, `get.opentofu.org` | CLI downloads + provider registries |
| Cloud CLIs | `awscli.amazonaws.com`, `packages.microsoft.com`, `packages.cloud.google.com`, `dl.google.com` | AWS CLI zip + Azure/gcloud GPG-signed apt repos |
| Cloud control-plane (starters) | `sts.amazonaws.com`, `management.azure.com`, `login.microsoftonline.com`, `graph.microsoft.com`, `accounts.google.com`, `oauth2.googleapis.com`, `*.googleapis.com` | basic identity/ARM/`gcloud auth` — **extend per provider/region** |
| GitHub | `github.com`, `api.github.com`, `codeload.github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com` | Pulumi/ESC/OpenTofu binaries, provider plugins, `gh`, APM repos |
| Registries | `registry.npmjs.org`, `pypi.org`, `files.pythonhosted.org`, `proxy.golang.org`, `sum.golang.org`, `storage.googleapis.com` | your IaC program's deps + provisioning |
| APM / MCP | `aka.ms`, `context7.com`, `*.context7.com` | APM installer, Context7 MCP |

`.NET` hosts (`dot.net`, `builds.dotnet.microsoft.com`, `api.nuget.org`,
`*.nuget.org`) are present but commented out — uncomment them together with
`ISK_INSTALL_DOTNET="1"`.

## Wildcard semantics (important)

The proxy enforces only:

- **exact host** — `api.example.com` (defaults to port 443), or with a port
  `api.example.com:8080`.
- **single-label wildcard** — `*.example.com` matches exactly one label:
  `s3.example.com` ✓, but `example.com` ✗ and `a.b.example.com` ✗.

Multi-label wildcards (`**.example.com`), CIDRs and port ranges are declared-but-
not-enforced today, and middle-position wildcards
(`bedrock-runtime.*.amazonaws.com`) aren't part of the format. **List regional
endpoints explicitly.**

## Cloud provider starters

The basic identity/control-plane hosts above are already allowed, so
`aws sts get-caller-identity`, `az login` and `gcloud auth` work out of the box.
For real work you still need the **regional service** and **object-storage**
endpoints your stacks call — add them to `kit/spec.yaml` →
`permissions.network.allow` and recreate the sandbox.

```yaml
# --- AWS (SigV4; also pass AWS_* creds — see docs/credentials.md) ---
- sts.amazonaws.com                   # (already included)
- s3.amazonaws.com
- s3.us-east-1.amazonaws.com          # add each region's S3 host explicitly
- ec2.us-east-1.amazonaws.com         # and each regional service host you use
- iam.amazonaws.com

# --- Azure ---
- management.azure.com
- login.microsoftonline.com
- graph.microsoft.com
- "*.blob.core.windows.net"           # single-label wildcard: one account label

# --- GCP ---
- "*.googleapis.com"                  # compute.googleapis.com, storage.googleapis.com, …
- oauth2.googleapis.com
- accounts.google.com

# --- providers you use ---
- api.civo.com
- api.scaleway.com                    # + account.scaleway.com, *.scw.cloud
- api.exoscale.com
- api.digitalocean.com
- api.vultr.com
- api.linode.com
- api.hetzner.cloud
```

These are starting points, not exhaustive — each provider's SDK may touch extra
hosts (object storage, OIDC, metadata). Discover the real set empirically:

## Discovering what's blocked

Run once, then read the proxy log — every blocked row is a host to add:

```bash
sbx policy log <sandbox-name>          # HOST column lists blocked (and allowed) requests
```

Add the host to `permissions.network.allow`, recreate the sandbox, repeat until
the blocked list is empty. Provider **plugins** download on first use from
GitHub / `get.pulumi.com` (already allowed); a plugin that pulls from a provider
CDN will show up here too.

## Package-manager gotcha

`apt-get update` normally refreshes **every** configured source, not just the one
you asked for — so one unreachable source fails the whole update under deny-all.
The kit's Azure/gcloud installs sidestep this by refreshing **only** their own
list (`apt-get update -o Dir::Etc::sourcelist=… -o Dir::Etc::sourceparts=-`), so
they need just `packages.microsoft.com` / `packages.cloud.google.com` — not the
base Ubuntu/Docker sources.

If you add your own `apt-get update` step, remember the base `*-docker` image
pre-adds `download.docker.com` — allow it (and `archive.ubuntu.com`,
`security.ubuntu.com`, `ports.ubuntu.com` for cross-arch) or it fails under
deny-all.
