# Runbooks

Starter IaC examples, dropped into `~/runbooks/` in the sandbox by the kit. They
are **credential-free** — each runs against a demo provider with no cloud
account, so you can smoke-test the toolchain the moment the sandbox is up.

| Runbook | Tool | Try it |
|---|---|---|
| `pulumi-random-ts/` | Pulumi (TypeScript) | `cd ~/runbooks/pulumi-random-ts && npm install && pulumi stack init dev && pulumi preview` |
| `terraform-random/` | Terraform **and** OpenTofu | `cd ~/runbooks/terraform-random && terraform init && terraform plan` (or `tofu init && tofu plan`) |

Notes:
- Pulumi: with a bound Pulumi token (`PULUMI_ACCESS_TOKEN` is proxy-managed) the
  stack lives in Pulumi Cloud; otherwise run `pulumi login --local` first.
- Terraform/OpenTofu share the same `main.tf` — `terraform` pulls providers from
  `registry.terraform.io`, `tofu` from `registry.opentofu.org` (both allow-listed).
- The `random` provider needs no credentials, so these preview/plan cleanly.

For real cloud resources (AWS/Azure/GCP) see [`cloud-examples.md`](cloud-examples.md)
— those need credentials (see `docs/credentials.md`) and the relevant endpoints
added to the kit's network allow-list (see `docs/network.md`).
