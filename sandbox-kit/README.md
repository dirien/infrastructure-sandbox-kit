# Infrastructure sandbox kit (one artifact)

A `kind: sandbox` kit. It names the prebuilt template image and carries the
same declarations as the [`../kit`](../kit) mixin: the network allow-list, the
Pulumi credential, the environment defaults, the setup steps and the agent
instructions. One `--kit` flag brings up the whole IaC workstation:

```bash
sbx run --kit ghcr.io/dirien/infrastructure-sandbox-kit:latest .
```

A sandbox kit defines the agent itself, so there is no separate agent name to
pass. If your `sbx` build still expects one, use the kit's `name`, which is
`infrastructure-sandbox`. To see what the kit declares:

```bash
sbx kit inspect ghcr.io/dirien/infrastructure-sandbox-kit:latest --json
```

## Which artifact do I want?

- This sandbox kit: one reference that brings the image and the rules together,
  with nothing else to remember.
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
