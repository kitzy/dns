# DNS Zone Management with Terraform and Route53

This repository manages Route53 DNS hosted zones using Terraform. Zone definitions live in [`dns_zones/`](dns_zones) as YAML files.

## Workflow

* **Pull requests** – A GitHub Action runs [`yamllint`](https://yamllint.readthedocs.io) and `terraform validate` to ensure the YAML and Terraform configuration are syntactically correct.
* **Merge to `main`** – Another workflow runs `terraform apply` to create, update, or remove Route53 zones and records so they match the files in this repo. Zones removed from the repository are deleted from Route53.
* NS and SOA records are never managed and remain untouched in existing zones.

## Adding or modifying zones

1. Create a new YAML file in `dns_zones/` with the zone name. See the existing files for structure.
2. Open a pull request. The lint workflow validates the YAML.
3. After the PR is merged to `main`, the apply workflow syncs Route53 so it matches the repository.

## AWS and Terraform setup

1. Create an S3 bucket and DynamoDB table for Terraform state and locking.
2. Add the following GitHub repository secrets:
   * `AWS_ACCESS_KEY_ID`
   * `AWS_SECRET_ACCESS_KEY`
   * `AWS_REGION`
   * `TF_BACKEND_BUCKET` – name of the S3 bucket
   * `TF_BACKEND_KEY` – path within the bucket for the state file (e.g. `route53/terraform.tfstate`)
   * `TF_BACKEND_DYNAMODB_TABLE` – DynamoDB table used for state locking
3. Optionally copy `backend.hcl.example` to `backend.hcl` for local development and run `terraform init -backend-config=backend.hcl`.

## Local validation

```bash
yamllint dns_zones
terraform fmt -check
terraform init -backend=false
terraform validate
```

These commands are the same checks run in CI.

## Notes

* The Terraform configuration automatically ignores NS and SOA records.
* Zone files must remain YAML; do not commit `terraform.tfstate` or `.terraform` directories.
