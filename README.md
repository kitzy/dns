# DNS Zone Management with Terraform

This## Terraform Cloud and Provider Configuration

1. Sign in to [Terraform Cloud](https://app.terraform.io/) and create an organization.
2. Create a workspace named `dns` and set its execution mode to **Local**.
3. Generate a user API token from *User Settings → Tokens*.
4. In the GitHub repository settings, add the following secrets:
   * `AWS_ACCESS_KEY_ID` (for Route53 zones)
   * `AWS_SECRET_ACCESS_KEY` (for Route53 zones)
   * `AWS_REGION` (for Route53 zones)
   * `CLOUDFLARE_API_TOKEN` (for Cloudflare zones)
   * `TF_API_TOKEN` – the Terraform Cloud API token from step 3
5. For local development, run `terraform login` once to store your API token.
6. Before running Terraform locally, export your provider credentials, e.g.
   ```bash
   # For Route53 zones
   export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=...
   export TF_VAR_AWS_REGION=$AWS_REGION
   
   # For Cloudflare zones
   export TF_VAR_CLOUDFLARE_API_TOKEN=your_cloudflare_token
   ```ges DNS hosted zones using Terraform with support for both AWS Route53 and Cloudflare providers. Zone definitions live in [`dns_zones/`](dns_zones) as YAML files, and the Terraform configuration resides in [`terraform/`](terraform).

> **Important:** This is my production DNS repository. If you fork or clone it, delete the contents of `dns_zones/` and add your own zones before running any Terraform commands. Otherwise you risk creating, modifying, or deleting DNS records for domains you do not control.

## Workflow

* **Pull requests** – Separate checks run for validation and planning. The validation job runs:
  - Zone configuration validation (checks provider field and structure)
  - [`yamllint`](https://yamllint.readthedocs.io) for YAML syntax
  - `terraform fmt -check` for Terraform formatting
  
  The plan job runs `terraform init`, `terraform validate`, and `terraform plan` to show proposed changes.
* **Merge to `main`** – Another workflow runs `terraform apply` to create, update, or remove DNS zones and records so they match the files in this repo. Zones removed from the repository are deleted from the configured provider (Route53 or Cloudflare).
* NS and SOA records are never managed and remain untouched in existing zones.
* **Nightly cleanup** – A scheduled workflow (also runnable manually) deletes any DNS records not defined in `dns_zones/` to revert manual changes. Route53 represents wildcard names as \052; zone files should use a quoted `*`, and the cleanup script normalizes this internally. Note: Currently only supports Route53 cleanup.

## Provider Selection

Each zone can specify which DNS provider to use by setting the `provider` field in the YAML file:

- `route53` - Uses AWS Route53  
- `cloudflare` - Uses Cloudflare DNS

**Route53 zones** support all routing policies (weighted, latency, geolocation, failover, multivalue).  
**Cloudflare zones** currently support simple routing only.

⚠️ **Important**: The `provider` field is **required** in all zone files. The validation workflow will fail if this field is missing or contains an unsupported provider.

```yaml
zone_name: "example.com"
provider: cloudflare  # or route53 (default)
records:
  - name: "example.com"
    type: A
    ttl: 300
    values:
      - "1.2.3.4"
```

## Adding or modifying zones

1. Create a new YAML file in `dns_zones/` with the zone name. See the existing files for structure.
2. Specify the `provider` field (`route53` or `cloudflare`). If omitted, defaults to `route53`.
3. Open a pull request. Lint and plan workflows validate the YAML and preview changes.
4. After the PR is merged to `main`, the apply workflow syncs the DNS provider so it matches the repository.

### Zone format

Each zone file supports the following top-level keys:

| key | required | description |
|-----|----------|-------------|
| `zone_name` | yes | The domain name for the zone |
| `provider` | no | DNS provider: `route53` (default) or `cloudflare` |
| `records` | yes | Array of DNS records for the zone |

### Record format

Each entry under `records:` supports the following keys:

| key | required | description |
|-----|----------|-------------|
| `name` | yes | Record name (use the zone name for apex records) |
| `type` | yes | DNS record type (e.g. `A`, `CNAME`) |
| `ttl` | yes | Time to live in seconds |
| `values` | yes | List of record values |
| `set_identifier` | no | Identifier for routing policies (Route53 only) |
| `routing_policy` | no | Object describing a routing policy (Route53 only) |

When `routing_policy` is omitted, records use **simple** routing. Routing policies are only supported for Route53 zones. Supported policy types are `weighted`, `latency`, `geolocation`, `failover`, and `multivalue`. See the example below for usage.

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

1. Sign in to [Terraform Cloud](https://app.terraform.io/) and create an organization.
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
# Install dependencies (one time)
pip install yamllint pyyaml

# Validate zone configuration
python3 scripts/validate_zones.py

# Lint YAML files
yamllint dns_zones

# Validate Terraform
cd terraform
terraform fmt -check
terraform init
terraform validate
terraform plan -no-color -input=false
```

These commands match the CI checks.

## Notes

* The Terraform configuration automatically ignores NS and SOA records for both providers.
* Zone files must remain YAML; do not commit `terraform.tfstate` or `.terraform` directories.
* This configuration supports both AWS Route53 and Cloudflare DNS providers.
* `terraform apply` and the cleanup workflow will overwrite DNS records to match this repository, so review changes carefully.
* Commands require valid credentials for the providers you're using:
  - Route53 zones: AWS credentials with Route53 permissions
  - Cloudflare zones: Cloudflare API token with Zone:Edit permissions
* Routing policies (weighted, latency, etc.) are only supported for Route53 zones.
* The cleanup script currently only supports Route53 zones.
