# Infrastructure sandbox kit (one artifact)

A `kind: sandbox` kit. It names the prebuilt template image and carries the
same declarations as the [`../kit`](../kit) mixin: the network allow-list, the
Pulumi credential, the environment defaults, the setup steps and the agent
instructions. One `--kit` flag brings up the whole IaC workstation:

```bash
sbx run --kit ghcr.io/dirien/infrastructure-sandbox-kit:v0.7.0 infrastructure-sandbox .
```

A sandbox kit defines its own agent, named after the kit, and `sbx run`
requires exactly that agent name: `infrastructure-sandbox` (passing `claude`,
or leaving the name out, is an error). The runtime inside is still Claude
Code, because that is what the pinned image ships. To see what the kit
declares:

```bash
sbx kit inspect ghcr.io/dirien/infrastructure-sandbox-kit:v0.7.0 --json
```

## Which artifact do I want?

- This sandbox kit: one reference that brings the image and the rules together;
  its agent name is `infrastructure-sandbox`.
- [`../kit`](../kit) mixin plus `--template`: you pick the image yourself, for
  example a locally built variant from `make load`.
- [`../kit`](../kit) mixin alone: zero build. The stock `claude` image installs
  the toolchain at create time.

All three paths produce the same sandbox.

## Keeping the specs in sync

The spec here mirrors [`../kit/spec.yaml`](../kit/spec.yaml). When you change
one, change both. The intended differences are the header comment, `kind`,
`name`, the `sandbox:` block, and the mixin-only `requires` field, which a
sandbox kit must not carry.

## Publishing

`scripts/push-kit.sh` stages this directory together with the shared
`kit/files/` tree (the runbooks) and pushes the result as
`ghcr.io/dirien/infrastructure-sandbox-kit`. The publish-kit workflow runs it
on every kit change on `main` (as `:latest`) and on version tags.
