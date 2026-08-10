# Network allow-list

Docker Sandboxes egress is default-deny: only hosts in the kit's
`permissions.network.allow` (composed with the base agent's) are reachable. This
kit ships the hosts that its own provisioning and the core IaC flow need. You add
the extra cloud and region endpoints and provider plugins you use.

## What the kit already allows

| Group | Hosts | Why |
|---|---|---|
| Pulumi | `api.pulumi.com`, `get.pulumi.com`, `mcp.ai.pulumi.com` | state/API, plugin/CLI downloads, hosted MCP |
| Terraform / OpenTofu | `releases.hashicorp.com`, `registry.terraform.io`, `registry.opentofu.org`, `get.opentofu.org` | CLI downloads + provider registries |
| Cloud CLIs | `awscli.amazonaws.com`, `packages.microsoft.com`, `packages.cloud.google.com`, `dl.google.com` | AWS CLI zip + Azure/gcloud GPG-signed apt repos |
| Cloud control-plane (starters) | `sts.amazonaws.com`, `management.azure.com`, `login.microsoftonline.com`, `graph.microsoft.com`, `accounts.google.com`, `oauth2.googleapis.com`, `*.googleapis.com` | basic identity, ARM, and `gcloud auth`; extend per provider and region |
| GitHub | `github.com`, `api.github.com`, `codeload.github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com`, `release-assets.githubusercontent.com` | Pulumi/OpenTofu binaries, provider plugins, `gh`, the APM CLI release tarballs, the APM skill repos |
| Registries | `registry.npmjs.org`, `pypi.org`, `files.pythonhosted.org`, `proxy.golang.org`, `sum.golang.org`, `storage.googleapis.com` | your IaC program's deps + provisioning |

The `.NET` hosts (`dot.net`, `builds.dotnet.microsoft.com`, `api.nuget.org`,
`*.nuget.org`) are present but commented out. Uncomment them together with
`ISK_INSTALL_DOTNET="1"`.

## Pattern syntax

Docker's network policy supports these resource patterns (per
[policy concepts](https://docs.docker.com/ai/sandboxes/governance/concepts/#network-rules)):

| Pattern | Example | Matches |
|---|---|---|
| Exact host | `example.com` | `example.com` only, not subdomains |
| Host with port | `example.com:443` | `example.com` on port 443 |
| Single-level wildcard | `*.example.com` | one label: `api.example.com` |
| Multi-level wildcard | `**.example.com` | any depth: `api.example.com`, `v2.api.example.com` |
| CIDR range | `10.0.0.0/8`, `2001:db8::/32` | IPv4 and IPv6 |

`example.com` and `*.example.com` don't cover each other; list both if you need
the root and its subdomains. A kit's `permissions.network.allow` is the kit's own
egress list; it is distinct from (and composed with) the organization- and
local-level governance policy rules that use this same syntax.

One kit-spec v2 caveat: in the kit's list only exact hosts, `host:port` and
single-label `*.host` patterns are enforced. `**.host` and CIDR entries parse
but don't open egress (yet), so express multi-level needs as explicit hosts or
single-label wildcards — or put them in governance policy, where they do work.

Middle-position wildcards like `bedrock-runtime.*.amazonaws.com` aren't part of
the format. For AWS regional endpoints in the kit's list, name the regional
hosts you use (`**.amazonaws.com` only takes effect in governance policy).

## Cloud provider starters

The basic identity and control-plane hosts above are already allowed, so
`aws sts get-caller-identity`, `az login` and `gcloud auth` work without extra
setup. For real work you still need the regional service and object-storage
endpoints your stacks call. Add them to `permissions.network.allow` in
`kit/spec.yaml` and recreate the sandbox.

```yaml
# AWS (SigV4; also pass AWS_* creds, see docs/credentials.md)
- sts.amazonaws.com                   # (already included)
- s3.amazonaws.com
- s3.us-east-1.amazonaws.com          # add each region's S3 host explicitly
- ec2.us-east-1.amazonaws.com         # and each regional service host you use
- iam.amazonaws.com

# Azure
- management.azure.com
- login.microsoftonline.com
- graph.microsoft.com
- "*.blob.core.windows.net"           # single-label wildcard: one account label

# GCP
- "*.googleapis.com"                  # compute.googleapis.com, storage.googleapis.com, ...
- oauth2.googleapis.com
- accounts.google.com

# providers you use
- api.civo.com
- api.scaleway.com                    # + account.scaleway.com, *.scw.cloud
- api.exoscale.com
- api.digitalocean.com
- api.vultr.com
- api.linode.com
- api.hetzner.cloud
```

These are starting points, not a complete list. Each provider's SDK may touch
extra hosts (object storage, OIDC, metadata), so find the real set by running it.

## Discovering what's blocked

Run once, then read the proxy log. Every blocked row is a host to add:

```bash
sbx policy log <sandbox-name>          # HOST column lists blocked (and allowed) requests
```

Add the host to `permissions.network.allow`, recreate the sandbox, and repeat
until the blocked list is empty. Provider plugins download on first use from
GitHub or `get.pulumi.com` (already allowed); a plugin that pulls from a provider
CDN shows up here too.

## Package-manager gotcha

`apt-get update` normally refreshes every configured source, not just the one you
asked for, so one unreachable source fails the whole update under deny-all. The
kit's Azure and gcloud installs avoid this by refreshing only their own list
(`apt-get update -o Dir::Etc::sourcelist=… -o Dir::Etc::sourceparts=-`), so they
need only `packages.microsoft.com` and `packages.cloud.google.com`, not the base
Ubuntu and Docker sources.

If you add your own `apt-get update` step, remember that the base `*-docker` image
pre-adds `download.docker.com`. Allow it (and `archive.ubuntu.com`,
`security.ubuntu.com`, `ports.ubuntu.com` for cross-arch coverage) or it fails
under deny-all.
