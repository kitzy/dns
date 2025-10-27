# DNS Zone Management with Terraform

## Terraform Cloud and Provider Configuration

1. Sign in to [Terraform Cloud](https://app.terraform.io/) and create an organization.
2. Create a workspace named `dns` and set its execution mode to **Local**.
3. Generate a user API token from *User Settings → Tokens*.
4. In the GitHub repository settings, add the following secrets:
   * `AWS_ACCESS_KEY_ID` (for Route53 zones)
   * `AWS_SECRET_ACCESS_KEY` (for Route53 zones)
   * `AWS_REGION` (for Route53 zones)
   * `CLOUDFLARE_API_TOKEN` (for Cloudflare zones)
   * `CLOUDFLARE_ACCOUNT_ID` (for Cloudflare zones)
   * `TF_API_TOKEN` – the Terraform Cloud API token from step 3
5. For local development, run `terraform login` once to store your API token.
6. Before running Terraform locally, export your provider credentials, e.g.
   ```bash
   # For Route53 zones
   export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_REGION=...
   export TF_VAR_AWS_REGION=$AWS_REGION
   
   # For Cloudflare zones
   export TF_VAR_CLOUDFLARE_API_TOKEN=your_cloudflare_token
   export TF_VAR_CLOUDFLARE_ACCOUNT_ID=your_cloudflare_account_id
   ```ges DNS hosted zones using Terraform with support for both AWS Route53 and Cloudflare providers. Zone definitions live in [`dns_zones/`](dns_zones) as YAML files, and the Terraform configuration resides in [`terraform/`](terraform).

> **Important:** This is my production DNS repository. If you fork or clone it, delete the contents of `dns_zones/` and add your own zones before running any Terraform commands. Otherwise you risk creating, modifying, or deleting DNS records for domains you do not control.

## Workflow

* **Pull requests** – Separate checks run for validation and planning. The validation job runs:
  - Zone configuration validation (checks provider/providers field and structure)
  - Validates that `proxied: true` is only used with supported record types (A, AAAA, CNAME)
  - Warns (non-blocking) if `proxied` field is used on non-Cloudflare zones
  - [`yamllint`](https://yamllint.readthedocs.io) for YAML syntax
  - `terraform fmt -check` for Terraform formatting
  
  The plan job runs `terraform init`, `terraform validate`, and `terraform plan` to show proposed changes.
* **Merge to `main`** – Another workflow runs `terraform apply` to create, update, or remove DNS zones and records so they match the files in this repo. Zones removed from the repository are deleted from the configured provider (Route53 or Cloudflare).
* NS and SOA records are never managed and remain untouched in existing zones.
* **Nightly cleanup** – A scheduled workflow (also runnable manually) deletes any DNS records not defined in `dns_zones/` to revert manual changes. Route53 represents wildcard names as \052; zone files should use a quoted `*`, and the cleanup script normalizes this internally. Note: Currently only supports Route53 cleanup.

## Provider Selection

Each zone can specify DNS provider(s) using either single or multi-provider formats:

### Single Provider Format
```yaml
zone_name: "example.com"
provider: route53  # or cloudflare
records: [...]
```

### Multi-Provider Format  
```yaml
zone_name: "example.com"
providers:
  - route53
  - cloudflare
records: [...]
```

**Supported providers:**
- `route53` - AWS Route53 (supports all routing policies)
- `cloudflare` - Cloudflare DNS (simple routing only)

### 🔄 Safe Zone Migration

The multi-provider format enables **zero-downtime migrations**:

1. **Start with Route53**: `provider: route53`
2. **Add Cloudflare**: Change to `providers: [route53, cloudflare]`
3. **Update NS records** at your registrar to point to Cloudflare
4. **Wait for DNS propagation** (24-48 hours)
5. **Remove Route53**: Change to `provider: cloudflare`

⚠️ **Important**: Either `provider` or `providers` field is **required**. You cannot specify both.

## Adding or modifying zones

1. Create a new YAML file in `dns_zones/` with the zone name. See the existing files for structure.
2. Specify either:
   - `provider: route53` or `provider: cloudflare` (single provider)
   - `providers: [route53, cloudflare]` (multi-provider for migrations)
3. Open a pull request. Lint and plan workflows validate the YAML and preview changes.
4. After the PR is merged to `main`, the apply workflow syncs the DNS provider so it matches the repository.

### Zone format

Each zone file supports the following top-level keys:

| key | required | description |
|-----|----------|-------------|
| `zone_name` | yes | The domain name for the zone |
| `provider` | no* | Single DNS provider: `route53` or `cloudflare` |
| `providers` | no* | List of DNS providers: `[route53, cloudflare]` |

*Either `provider` or `providers` is required, but not both.
| `records` | yes | Array of DNS records for the zone |

### Record format

Each entry under `records:` supports the following keys:

| key | required | description |
|-----|----------|-------------|
| `name` | yes | Record name (use the zone name for apex records) |
| `type` | yes | DNS record type (e.g. `A`, `CNAME`) |
| `ttl` | yes | Time to live in seconds |
| `values` | yes | List of record values |
| `proxied` | no | Enable Cloudflare proxy (orange cloud). Defaults to `false` (DNS only). Only applicable for Cloudflare zones. |
| `set_identifier` | no | Identifier for routing policies (Route53 only) |
| `routing_policy` | no | Object describing a routing policy (Route53 only) |

When `routing_policy` is omitted, records use **simple** routing. Routing policies are only supported for Route53 zones. Supported policy types are `weighted`, `latency`, `geolocation`, `failover`, and `multivalue`. See the example below for usage.

**Route53 routing policy example:**
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

**Cloudflare proxy example:**
```yaml
zone_name: "example.com"
provider: cloudflare
records:
  - name: "example.com"
    type: A
    ttl: 300
    values: ["192.0.2.1"]
    proxied: true  # Enable Cloudflare proxy (orange cloud)
  - name: "www"
    type: CNAME
    ttl: 300
    values: ["example.com"]
    proxied: true
  - name: "direct"
    type: A
    ttl: 300
    values: ["192.0.2.2"]
    # proxied field omitted - defaults to false (DNS only)
```

> **Note on Cloudflare Proxy:** The `proxied` field enables Cloudflare's proxy (orange cloud icon), which provides DDoS protection, CDN, and SSL/TLS. Only certain record types can be proxied (A, AAAA, CNAME). Other record types like MX, TXT, NS, and SRV must have `proxied: false` or omit the field. **The validation script will fail if you try to set `proxied: true` on unsupported record types.** When `proxied: true`, **the TTL value in your YAML file is automatically ignored and set to 1** (per Cloudflare's API requirement). You can specify any TTL value in the YAML for consistency, but Terraform will override it to 1 for proxied records.

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
