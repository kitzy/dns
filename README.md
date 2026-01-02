# DNS Zone Management with Terraform

This repository manages DNS hosted zones using Terraform with support for both AWS Route53 and Cloudflare providers. Zone definitions live in [`dns_zones/`](dns_zones) as YAML files, and the Terraform configuration resides in [`terraform/`](terraform).

## 🔒 Security Scanning

This repository includes **automated weekly security scans** to detect DNS vulnerabilities:
- 🚨 **Subdomain takeover detection** - Identifies CNAMEs pointing to unclaimed cloud services
- 🔗 **Broken CNAME detection** - Finds CNAMEs pointing to non-existent domains
- 🔍 **Dangling DNS records** - Detects records pointing to decommissioned resources

Scans run every Monday at 9 AM UTC and on pull requests affecting DNS zones. Critical issues automatically create GitHub issues for review.

👉 **[Learn more about DNS Security Scanning](SECURITY_SCANNING.md)**

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
* **Nightly cleanup** – A scheduled workflow (also runnable manually) deletes any DNS records not defined in `dns_zones/` to revert manual changes. The cleanup scripts only process zones that have corresponding YAML files in the repository; any zones in Route53 or Cloudflare that aren't defined in the repo are completely ignored and left untouched. Route53 represents wildcard names as \052; zone files should use a quoted `*`, and the cleanup script normalizes this internally.

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

## 🚇 Cloudflare Tunnels

Cloudflare Tunnels allow you to securely expose internal services (like Kubernetes clusters, private servers, or localhost) to the internet without opening inbound ports. This repository supports managing tunnel DNS records and routing configurations directly in your zone files.

### Prerequisites

1. **Create a tunnel** in Cloudflare (via `cloudflared` CLI or Zero Trust dashboard)
2. **Get the tunnel ID** from Cloudflare (visible in the Zero Trust dashboard or CLI output)
3. **Run the tunnel connector** on your server/cluster to establish the connection

### Tunnel Definitions

All tunnels are defined centrally in [`cloudflare_tunnels.yml`](cloudflare_tunnels.yml) at the repository root. This allows you to reference the same tunnel across multiple DNS zones.

**cloudflare_tunnels.yml:**
```yaml
tunnels:
  homelab-k3s:
    tunnel_id: "a80b484c-d2e9-484b-bf01-ba385ee9be7e"
    description: "Homelab Kubernetes cluster tunnel"
  
  office-server:
    tunnel_id: "xyz789abc-1234-5678-90ab-cdef12345678"
    description: "Office network tunnel"
```

### Using Tunnels in Zone Files

Reference defined tunnels in your DNS zone files using TUNNEL records:

```yaml
zone_name: "example.com"
provider: cloudflare

records:
  # Regular DNS records...
  
  # Tunnel record - routes subdomain to internal service
  - name: "app"
    type: TUNNEL
    ttl: 300
    tunnel:
      name: "homelab-k3s"  # References tunnel from cloudflare_tunnels.yml
      service: "http://myapp.default.svc.cluster.local:8080"
```

### Zone-Specific Tunnel Overrides (Optional)

You can also define tunnels directly in zone files if needed. Zone-specific definitions take precedence over global ones:

```yaml
zone_name: "example.com"
provider: cloudflare

# Optional: Override or add zone-specific tunnels
tunnels:
  special-tunnel:
    tunnel_id: "zone-specific-tunnel-id"

records:
  - name: "special"
    type: TUNNEL
    ttl: 300
    tunnel:
      name: "special-tunnel"
      service: "http://special-service:80"
```

### Supported Service Protocols

The `service` field supports various protocols:

- **HTTP/HTTPS**: `http://internal-service:80`, `https://internal-service:443`
- **TCP**: `tcp://database-server:5432`
- **SSH**: `ssh://internal-host:22`
- **RDP**: `rdp://windows-server:3389`
- **Unix sockets**: `unix:/path/to/socket`, `unix+tls:/path/to/socket`

### How It Works

When you define a TUNNEL record, Terraform automatically:

1. **Creates a CNAME record** pointing to `<tunnel-id>.cfargotunnel.com`
2. **Configures tunnel routing** to map the hostname to your internal service
3. **Enables Cloudflare proxy** (always proxied for tunnels)

The CNAME record allows DNS resolution to find the tunnel, while the tunnel configuration tells Cloudflare where to route traffic.

### Multiple Services on One Tunnel

You can route multiple hostnames through the same tunnel across different zones:

**kitzy.net zone:**
```yaml
records:
  - name: "grafana"
    type: TUNNEL
    tunnel:
      name: "homelab-k3s"
      service: "http://grafana.monitoring.svc:3000"
```

**kitzy.com zone:**
```yaml
records:
  - name: "nextcloud"
    type: TUNNEL
    tunnel:
      name: "homelab-k3s"  # Same tunnel, different zone
      service: "http://nextcloud.default.svc:80"
```

### Tunnel Setup Steps

1. **Install cloudflared** on your server/cluster
   ```bash
   # Example for Linux
   wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
   sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
   sudo chmod +x /usr/local/bin/cloudflared
   ```

2. **Authenticate and create tunnel**
   ```bash
   cloudflared tunnel login
   cloudflared tunnel create my-tunnel-name
   # Note the tunnel ID from the output
   ```

3. **Add tunnel to cloudflare_tunnels.yml**
   ```yaml
   tunnels:
     my-tunnel-name:
       tunnel_id: "your-tunnel-id-here"
       description: "Description of your tunnel"
   ```

4. **Reference tunnel in zone file(s)**
   ```yaml
   records:
     - name: "app"
       type: TUNNEL
       ttl: 300
       tunnel:
         name: "my-tunnel-name"
         service: "http://internal-service:80"
   ```

5. **Apply Terraform changes** to create DNS records and routing config

6. **Run the tunnel**
   ```bash
   cloudflared tunnel run my-tunnel-name
   ```

### Important Notes

- **Tunnels must exist** in Cloudflare before adding them to `cloudflare_tunnels.yml`
- **Tunnel records are Cloudflare-only** - they cannot be used with Route53
- **Global tunnel definitions** in `cloudflare_tunnels.yml` can be referenced by any zone
- **Zone-specific tunnels** (defined in zone files) override global ones with the same name
- **The validation script** checks that referenced tunnels are defined (either globally or zone-specific)
- **Cleanup script** properly handles tunnel-generated CNAME records
- **TTL is informational** - tunnel CNAMEs are always proxied (TTL=1)

## Nameserver Delegation

### Delegating to Different Nameservers

To delegate a domain to use Cloudflare nameservers, add NS records to the zone file:

```yaml
zone_name: "example.com"
providers:
  - route53
  - cloudflare
records:
  - name: "example.com"
    type: NS
    ttl: 172800
    values:
      - "achiel.ns.cloudflare.com"
      - "ullis.ns.cloudflare.com"
  # ... other records
```

**How this works:**
- NS records in the zone file are used **only** to update the domain registrar
- **If NS records are present**, Terraform assumes the domain is registered through AWS Route53 and automatically updates the registration
- **If NS records are omitted**, no registrar updates are performed (use this for domains registered elsewhere)
- NS records are **NOT** created in the Route53 or Cloudflare hosted zones (they're auto-managed by AWS/Cloudflare)
- DNS resolution for the domain is delegated to Cloudflare
- The TTL of 172800 (48 hours) is recommended for NS records

**Migration workflow:**
1. Add both `route53` and `cloudflare` as providers
2. Add NS records pointing to Cloudflare nameservers in the zone file (as shown above)
3. Commit and apply via Terraform - **nameservers are automatically updated at the registrar**
4. Wait for DNS propagation (24-48 hours)
5. Optionally remove Route53 from providers list once fully migrated

**Important:** This only works for domains registered through AWS Route53. If your domain is registered elsewhere (GoDaddy, Namecheap, etc.), you must manually update the nameservers at your registrar.

### Checking Nameservers

After applying Terraform changes, you can view the assigned nameservers:

```bash
cd terraform
terraform output route53_nameservers
terraform output cloudflare_nameservers
terraform output domain_registrar_nameservers
```

The `domain_registrar_nameservers` output shows which nameservers are configured at the domain registrar level for AWS Route53 registered domains.

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
| `records` | yes | Array of DNS records for the zone |

*Either `provider` or `providers` is required, but not both.

### Record format

Each entry under `records:` supports the following keys:

| key | required | description |
|-----|----------|-------------|
| `name` | yes | Record name (use the zone name for apex records) |
| `type` | yes | DNS record type (e.g. `A`, `CNAME`, `TUNNEL`) |
| `ttl` | yes | Time to live in seconds |
| `values` | conditional | List of record values (not used for TUNNEL type) |
| `tunnel` | conditional | Tunnel configuration object (required for TUNNEL type) |
| `proxied` | no | Enable Cloudflare proxy (orange cloud). Defaults to `false` (DNS only). Only applicable for Cloudflare zones. |
| `set_identifier` | no | Identifier for routing policies (Route53 only) |
| `routing_policy` | no | Object describing a routing policy (Route53 only) |

**Record type specifics:**
- Standard record types (A, AAAA, CNAME, MX, TXT, etc.) require `values`
- TUNNEL records require `tunnel` object with `name` and `service` fields
- TUNNEL records are always proxied (ignore `proxied` field)
- Routing policies are only supported for Route53 zones

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
pip install yamllint pyyaml dnspython

# Validate zone configuration
python3 scripts/validate_zones.py

# Run security scan
python3 scripts/security_scan.py --verbose

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
* The cleanup scripts only process zones defined in `dns_zones/` with the appropriate provider configuration. Any zones in Route53 or Cloudflare that don't have corresponding YAML files in the repository are completely ignored.
