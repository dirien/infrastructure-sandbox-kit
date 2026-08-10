# Credentials

Docker Sandboxes keep secret values in the `sbx` secret store, and a kit declares
how a stored secret is injected. `sbx secret set` reads the value interactively
(or from stdin), never as a plaintext argument.

## Pulumi Cloud token (wired by this kit)

The kit declares a `pulumi` credential (`credentials[].service` in the v2 spec)
whose `apiKey` block injects `Authorization: token <PAT>` on `api.pulumi.com`;
`proxyManaged: true` masks `PULUMI_ACCESS_TOKEN` in the container as a
proxy-managed placeholder. The kit only declares the requirement — the value is
bound from the host's secret store. Store the token:

```bash
# interactive (prompts, no echo):
sbx secret set -g pulumi

# or from stdin / an env var:
printf '%s\n' "$PULUMI_ACCESS_TOKEN" | sbx secret set -g pulumi
```

`-g` stores it globally (all sandboxes on this host); use `sbx secret set <sandbox> pulumi`
for one sandbox. After that, `pulumi login`, `pulumi up` and `pulumi env`
authenticate through the proxy, and the container only ever holds the
proxy-managed placeholder.

## Anthropic (Claude Code itself)

This kit runs the built-in `claude` agent, so `sbx` handles Claude's own
authentication. If you haven't set it up on this host yet:

```bash
sbx secret set -g anthropic          # or the interactive OAuth flow sbx offers
```

## Cloud provider credentials

The `aws`, `az` and `gcloud` CLIs (and the Pulumi, Terraform and OpenTofu
providers) are installed, but the kit does not inject cloud credentials, because
which clouds you target is per project. Three options:

### Option A (recommended): Pulumi ESC

Reach ESC through `pulumi env` (the standalone `esc` CLI was retired in 2026).
Keep cloud credentials in a Pulumi ESC environment and let Pulumi pull short-lived
creds through OIDC at `pulumi up` time, so nothing long-lived lands in the
sandbox. Add `api.pulumi.com` (already allowed) and your
cloud's STS/OIDC endpoints to the network allow-list ([`network.md`](network.md)).

### Option B: environment variables inside the sandbox

`sbx run` has no `-e`/`--env` flag. To set container-resident variables (for
example AWS's SigV4 credentials, which the proxy can't rewrite), write them to
`/etc/sandbox-persistent.sh`, which is sourced on every shell in the sandbox:

```bash
sbx exec -d <sandbox-name> bash -c \
  "printf 'export AWS_ACCESS_KEY_ID=%s\nexport AWS_SECRET_ACCESS_KEY=%s\nexport AWS_REGION=%s\n' \
   \"$AWS_ACCESS_KEY_ID\" \"$AWS_SECRET_ACCESS_KEY\" \"$AWS_REGION\" >> /etc/sandbox-persistent.sh"
```

(The `bash -c` wrapper is required so the `>>` redirect runs inside the sandbox.)
You can also authenticate the CLIs directly in-session:

- Azure: `az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID"`.
- GCP: `gcloud auth activate-service-account --key-file=<path>`.
- AWS: `aws configure` or `aws sso login`.

Allow the relevant management/auth hosts in the kit's `permissions.network.allow`
(see [`network.md`](network.md)).

### Option C: proxy-injected header credentials

For providers whose API uses a simple header token (Civo, Scaleway, and similar),
inject it like the Pulumi token, keyed by host, so the container never sees it:

```bash
sbx secret set-custom -g --host api.civo.com --env CIVO_TOKEN --value "$CIVO_TOKEN"
```

Whichever you choose, never commit credentials into code. The PostToolUse
secret-scan hook from the APM setup blocks edits that add obvious keys.

## Reference

- Credentials: <https://docs.docker.com/ai/sandboxes/security/credentials/>
- Custom environment variables: <https://docs.docker.com/ai/sandboxes/faq/#how-do-i-set-custom-environment-variables-inside-a-sandbox>
