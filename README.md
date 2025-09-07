# DNS Zone Management with Terraform and Route53

This repository manages Route53 DNS hosted zones using Terraform. Zone definitions live in [`dns_zones/`](dns_zones) as YAML files.

## Workflow

* **Pull requests** – Separate checks run for linting and planning. The lint job runs [`yamllint`](https://yamllint.readthedocs.io) and `terraform fmt -check`, and the plan job runs `terraform init`, `terraform validate`, and `terraform plan` to show proposed changes.
* **Merge to `main`** – Another workflow runs `terraform apply` to create, update, or remove Route53 zones and records so they match the files in this repo. Zones removed from the repository are deleted from Route53.
* NS and SOA records are never managed and remain untouched in existing zones.

## Adding or modifying zones

1. Create a new YAML file in `dns_zones/` with the zone name. See the existing files for structure.
2. Open a pull request. Lint and plan workflows validate the YAML and preview changes.
3. After the PR is merged to `main`, the apply workflow syncs Route53 so it matches the repository.

## Terraform Cloud and AWS configuration

1. Sign in to [Terraform Cloud](https://app.terraform.io/) and create an organization (e.g. `kitzy_net`).
2. Create a workspace named `dns` and set its execution mode to **Local**.
3. Generate a user API token from *User Settings → Tokens*.
4. In the GitHub repository settings, add the following secrets:
   * `AWS_ACCESS_KEY_ID`
   * `AWS_SECRET_ACCESS_KEY`
   * `AWS_REGION`
   * `TF_API_TOKEN` – the Terraform Cloud API token from step 3
5. For local development, run `terraform login` once to store your API token.

## Local validation

```bash
yamllint dns_zones
terraform fmt -check
terraform init
terraform validate
terraform plan -no-color -input=false
```

These commands match the CI checks.

## Notes

* The Terraform configuration automatically ignores NS and SOA records.
* Zone files must remain YAML; do not commit `terraform.tfstate` or `.terraform` directories.
