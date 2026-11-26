# Infrastructure sandbox kit (one artifact)

A kit-spec v2 `kind: sandbox` kit. It names the prebuilt template image and
carries the same declarations as the [`../kit`](../kit) mixin: the network allow-list, the
Pulumi credential, the environment defaults, the setup steps and the agent
instructions. One `--kit` flag brings up the whole IaC workstation:

```bash
sbx run --kit ghcr.io/dirien/infrastructure-sandbox-kit:v0.11.1 infrastructure-sandbox .
```

A sandbox kit defines its own agent, named after the kit, and `sbx run`
requires exactly that agent name: `infrastructure-sandbox` (passing `claude`,
or leaving the name out, is an error). The runtime inside is still Claude
Code, because that is what the pinned image ships. To see what the kit
declares:

```bash
sbx kit inspect ghcr.io/dirien/infrastructure-sandbox-kit:v0.11.1 --json
```

The sandbox kit name also works as the positional argument:
`sbx run ghcr.io/dirien/infrastructure-sandbox-kit:v0.11.1 .`.

## Which artifact do I want?

- This sandbox kit: one reference that brings the image and the rules together;
  its agent name is `infrastructure-sandbox`. Tools are baked in, so sandboxes
  start instantly. It runs Ubuntu 26.04, and the APM skills land in a
  directory of its own (no `--skills=off` needed).
- [`../kit`](../kit) mixin: zero build, layered onto Docker's built-in `claude`
  agent (Debian 13), which installs the toolchain at create time.

Both produce the same toolchain, APM setup and rules. The earlier
"template image + mixin" combination (`--template … --kit ./kit claude`) no
longer works: since sbx 0.51 the built-in `claude` agent is a kit-spec v3 kit,
and sbx refuses to mix it with v2 kits. Use this sandbox kit instead.

## Why it stays on kit-spec v2

sbx 0.54.1 still runs v2 `kind: sandbox` kits as standalone agents, and this kit
composes with nothing else, so the v2 grammar's single `sandbox.image` field is
the simplest way to name the prebuilt image. `sbx kit validate --offline`
checks it without a daemon or sign-in.

## Keeping the specs in sync

The declarations here mirror [`../kit/infrastructure.yaml`](../kit/infrastructure.yaml)
in the v2 grammar. When you change one, change both: `permissions.network.allow`
matches the v3 `network-policy@1` lists (minus the Debian apt hosts, which the
Ubuntu image doesn't use), `credentials` matches `credential@1`,
`environment.variables` matches the kit args, `setup.install`/`setup.startup`
match the `lifecycle@1` hooks, and `agentInstructions` matches `agent-context`.

## Publishing

`scripts/push-kit.sh` stages this directory together with the shared
`kit/files/` tree (the runbooks), validates it with `sbx kit validate --offline`
and pushes it with `sbx kit push` as `ghcr.io/dirien/infrastructure-sandbox-kit`.
The publish-kit workflow runs it on every kit change on `main` (as `:latest`)
and on version tags.
