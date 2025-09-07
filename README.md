# DNS Zone Management with Terraform and Route53

This repository manages Route53 DNS hosted zones using Terraform. Zone definitions live in [`dns_zones/`](dns_zones) as YAML files, and the Terraform configuration resides in [`terraform/`](terraform).

## Workflow

* **Pull requests** – Separate checks run for linting and planning. The lint job runs [`yamllint`](https://yamllint.readthedocs.io) and `terraform fmt -check`, and the plan job runs `terraform init`, `terraform validate`, and `terraform plan` to show proposed changes.
* **Merge to `main`** – Another workflow runs `terraform apply` to create, update, or remove Route53 zones and records so they match the files in this repo. Zones removed from the repository are deleted from Route53.
* NS and SOA records are never managed and remain untouched in existing zones.

## Adding or modifying zones

1. Create a new YAML file in `dns_zones/` with the zone name. See the existing files for structure.
2. Open a pull request. Lint and plan workflows validate the YAML and preview changes.
3. After the PR is merged to `main`, the apply workflow syncs Route53 so it matches the repository.

### Record format

Each entry under `records:` supports the following keys:

| key | required | description |
|-----|----------|-------------|
| `name` | yes | Record name (use the zone name for apex records) |
| `type` | yes | DNS record type (e.g. `A`, `CNAME`) |
| `ttl` | yes | Time to live in seconds |
| `values` | yes | List of record values |
| `set_identifier` | no | Identifier for routing policies |
| `routing_policy` | no | Object describing a routing policy |

When `routing_policy` is omitted, records use Route53's default **simple** routing. Supported policy types are `weighted`, `latency`, `geolocation`, `failover`, and `multivalue`. See the example below for usage.

```yaml
records:
  - name: "www"
    type: A
    ttl: 60
    values: ["1.2.3.4"]
    set_identifier: primary
    routing_policy:
      type: weighted
      weight: 100
  - name: "www"
    type: A
    ttl: 60
    values: ["5.6.7.8"]
    set_identifier: secondary
    routing_policy:
      type: weighted
      weight: 50
```

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
6. Before running Terraform locally, export your AWS credentials and region, e.g.
   ```bash
   export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=...
   export TF_VAR_AWS_REGION=$AWS_REGION
   ```

## Local validation

```bash
yamllint dns_zones
cd terraform
terraform fmt -check
terraform init
terraform validate
terraform plan -no-color -input=false
```

These commands match the CI checks.

## Notes

* The Terraform configuration automatically ignores NS and SOA records.
* Zone files must remain YAML; do not commit `terraform.tfstate` or `.terraform` directories.
