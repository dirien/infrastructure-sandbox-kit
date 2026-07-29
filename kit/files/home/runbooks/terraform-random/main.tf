# Credential-free Terraform / OpenTofu starter using the random provider.
# Works with both:  terraform init && terraform plan   |   tofu init && tofu plan

terraform {
  required_version = ">= 1.5"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

resource "random_pet" "name" {
  length = 2
}

resource "random_password" "password" {
  length  = 16
  special = true
}

output "pet_name" {
  value = random_pet.name.id
}

output "password" {
  value     = random_password.password.result
  sensitive = true
}
