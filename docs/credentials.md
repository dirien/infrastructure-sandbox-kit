# Credentials

Docker Sandboxes split the credential contract: a kit declares what it needs (a
service and where to inject it), and you declare where the value lives on your
host, in `~/.config/sbx/credentials.yaml` (`%APPDATA%\sbx\credentials.yaml` on
Windows). The container never learns your discovery locations, and for
proxy-injected credentials it never sees the secret itself.

The first time you run the kit, `sbx` prompts interactively to set up any binding
it needs. The recipes below are the non-interactive equivalents.

## Pulumi Cloud token (wired by this kit)

The kit injects `PULUMI_ACCESS_TOKEN` as `Authorization: token <PAT>` on
`api.pulumi.com`. Store the value and declare the binding:

```bash
# Store the token in sbx's secret store (global = all sandboxes on this host).
sbx secret set -g pulumi "$PULUMI_ACCESS_TOKEN"
```

```yaml
# ~/.config/sbx/credentials.yaml: declare the allowed domain for the binding.
bindings:
  pulumi:
    discovery: []                 # empty: the value comes from the secret store above
    allowedDomains:
      - api.pulumi.com
```

`pulumi login`, `pulumi up`, `esc`, and the rest now authenticate through the
proxy, and the container only ever holds `PULUMI_ACCESS_TOKEN=proxy-managed`.

Prefer discovery from an env var or file instead of the secret store? Drop the
`sbx secret set` and use:

```yaml
bindings:
  pulumi:
    discovery:
      - env: [PULUMI_ACCESS_TOKEN]
      - file: { path: "~/.pulumi/credentials.json", parser: "json:accessTokens.https://api.pulumi.com" }
    allowedDomains:
      - api.pulumi.com
```

## Anthropic (Claude Code itself)

This kit runs the built-in `claude` agent, so `sbx` handles Claude's own
authentication and you don't re-declare it here. If you haven't set it up on this
host yet:

```bash
sbx secret set -g anthropic "$ANTHROPIC_API_KEY"     # or use the interactive OAuth flow sbx offers
```

## Cloud provider credentials

The `aws`, `az` and `gcloud` CLIs (and the Pulumi, Terraform and OpenTofu
providers) are installed, but the kit does not inject cloud credentials, because
which clouds you target is per project. Two options:

### Option A (recommended): Pulumi ESC

`esc` is installed in the sandbox. Keep cloud credentials in a Pulumi ESC
environment and let Pulumi pull short-lived creds through OIDC at `pulumi up`
time, so nothing long-lived lands in the sandbox. Add `api.pulumi.com` (already
allowed) and your cloud's STS/OIDC endpoints to the network allow-list
([`network.md`](network.md)).

### Option B: pass credentials into the sandbox

For direct credentials, the delivery model differs by provider:

- AWS uses SigV4 request signing, which the proxy can't rewrite, so AWS
  credentials stay in the container, bounded by the network allow-list. Provide
  them as environment variables at run time and allow the AWS endpoints your stack
  calls:

  ```bash
  sbx run --template infrastructure-sandbox:latest --kit ./kit \
    -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_REGION \
    claude .
  ```

  (Confirm the exact `-e`/`--env` flag with `sbx run --help` on your version.)

  The `aws` CLI then works from the env vars directly, or run `aws configure` or
  `aws sso login` in-session.

- Azure: pass `ARM_*` or `AZURE_*` env vars, or authenticate the `az` CLI with a
  service principal:
  `az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID"`.

- GCP: pass `GOOGLE_CREDENTIALS` or `GOOGLE_APPLICATION_CREDENTIALS`, or point
  `gcloud` at a service-account key:
  `gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"`.
  Either can be sourced from ESC. Add each provider's management and auth hosts to
  the allow-list.

- Other providers you use with Pulumi (Civo, Scaleway, Exoscale, DigitalOcean,
  Vultr, Linode, Hetzner, OVH) each take a single API-token env var. Pass it with
  `-e` and allow the provider's API host.

Whichever you choose, never commit credentials into code. The PostToolUse
secret-scan hook from the APM setup blocks edits that add obvious keys.

## Reference

- Binding file shape, parsers, named variants, resolution order:
  <https://docs.docker.com/ai/sandboxes/> and the kit-author "bindings" topic.
- The kit declares only `service: pulumi`. Everything else above is host-side
  configuration you control.
