# Network allow-list

Docker Sandboxes egress is default-deny: only hosts in the kit's
`permissions.network.allow` (composed with the base agent's) are reachable. This
kit ships the hosts its own provisioning and the core Pulumi flow need — **you
add the hosts your clouds and provider plugins use.**

## What the kit already allows

| Group | Hosts | Why |
|---|---|---|
| Pulumi | `api.pulumi.com`, `get.pulumi.com`, `mcp.ai.pulumi.com` | state/API, plugin/CLI downloads, hosted MCP |
| GitHub | `github.com`, `api.github.com`, `codeload.github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com` | Pulumi/ESC binaries, provider plugins, `gh`, APM skill repos |
| Registries | `registry.npmjs.org`, `pypi.org`, `files.pythonhosted.org`, `proxy.golang.org`, `sum.golang.org`, `storage.googleapis.com` | your Pulumi program's deps + provisioning |
| APM / MCP | `aka.ms`, `context7.com`, `*.context7.com` | APM installer, Context7 MCP |

`.NET` hosts (`dot.net`, `builds.dotnet.microsoft.com`, `api.nuget.org`,
`*.nuget.org`) are present but commented out — uncomment them together with
`PSK_INSTALL_DOTNET="1"`.

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

Add the entries for the clouds you actually target to
`kit/spec.yaml` → `permissions.network.allow`, then recreate the sandbox.

```yaml
# --- AWS (SigV4; also pass AWS_* creds — see docs/credentials.md) ---
- sts.amazonaws.com
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

`apt-get update` / language package managers refresh **every** configured source,
not just the one you asked for. The kit's provisioning avoids `apt`, but if you
add an install step that uses it, remember the base `*-docker` image pre-adds
`download.docker.com` to apt sources — allow it (and `archive.ubuntu.com`,
`security.ubuntu.com`, `ports.ubuntu.com` for cross-arch) or `apt-get update`
fails under deny-all.
