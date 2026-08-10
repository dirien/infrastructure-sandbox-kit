# Cloud examples (need credentials)

Unlike the `random`-provider runbooks, these touch real clouds — so they need
credentials (see `docs/credentials.md`) **and** the relevant endpoints added to
the kit's `permissions.network.allow` (see `docs/network.md`). Snippets only;
copy into a workspace project.

## AWS S3 bucket

Pulumi (TypeScript) — `npm add @pulumi/aws`:

```ts
import * as aws from "@pulumi/aws";
const bucket = new aws.s3.BucketV2("demo", {});
export const bucketName = bucket.id;
```

Terraform / OpenTofu:

```hcl
terraform {
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } }
}
provider "aws" { region = "eu-central-1" }
resource "aws_s3_bucket" "demo" {}
output "bucket" { value = aws_s3_bucket.demo.id }
```

Allow-list: `sts.amazonaws.com` (included), plus your region's
`s3.<region>.amazonaws.com` and any service endpoints. AWS creds are
container-resident (SigV4) — pass `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`
/ `AWS_REGION`, or use `aws sso login`.

## Azure resource group

Pulumi — `npm add @pulumi/azure-native`:

```ts
import * as resources from "@pulumi/azure-native/resources";
const rg = new resources.ResourceGroup("demo", { location: "westeurope" });
export const rgName = rg.name;
```

Terraform / OpenTofu:

```hcl
terraform {
  required_providers { azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" } }
}
provider "azurerm" { features {} }
resource "azurerm_resource_group" "demo" {
  name     = "demo-rg"
  location = "West Europe"
}
```

Auth: `az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID"`
(or `ARM_*` env vars). `management.azure.com` / `login.microsoftonline.com` are
already allow-listed.

## GCP storage bucket

Pulumi — `npm add @pulumi/gcp`:

```ts
import * as gcp from "@pulumi/gcp";
const bucket = new gcp.storage.Bucket("demo", { location: "EU" });
export const bucketUrl = bucket.url;
```

Terraform / OpenTofu:

```hcl
terraform {
  required_providers { google = { source = "hashicorp/google", version = "~> 6.0" } }
}
provider "google" { project = "my-project", region = "europe-west1" }
resource "google_storage_bucket" "demo" {
  name     = "demo-bucket-unique"
  location = "EU"
}
```

Auth: `gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"`.
`*.googleapis.com` / `oauth2.googleapis.com` are already allow-listed.
