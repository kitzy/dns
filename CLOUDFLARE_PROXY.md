# Cloudflare Proxy Configuration

This document explains how to configure Cloudflare's proxy feature (orange cloud) for DNS records.

## Overview

Cloudflare's proxy feature provides:
- **DDoS protection** - Automatic mitigation of DDoS attacks
- **CDN** - Global content delivery network for faster page loads
- **SSL/TLS** - Free SSL certificates and encryption
- **WAF** - Web Application Firewall protection
- **Analytics** - Detailed traffic analytics
- **Performance** - Page rules, caching, and optimization

## Usage

Add the `proxied` field to any DNS record in your zone configuration:

```yaml
zone_name: "example.com"
provider: cloudflare
records:
  - name: "example.com"
    type: A
    ttl: 300
    values: ["192.0.2.1"]
    proxied: true  # Enable proxy (orange cloud)
```

## Default Behavior

**If the `proxied` field is omitted, it defaults to `false` (DNS only mode).**

This means:
- DNS records are **not proxied** by default
- You get DNS resolution only (grey cloud in Cloudflare dashboard)
- No DDoS protection, CDN, or other Cloudflare features
- Direct connection to your origin server

This default was chosen for safety and predictability, as not all services work correctly when proxied.

## Proxied vs. DNS Only

| Mode | Cloudflare Dashboard | Traffic Flow | Benefits | Use Cases |
|------|---------------------|--------------|----------|-----------|
| `proxied: true` | 🟠 Orange cloud | Client → Cloudflare → Origin | DDoS protection, CDN, SSL, WAF | Web traffic (HTTP/HTTPS) |
| `proxied: false` | ⚪ Grey cloud | Client → Origin (direct) | Direct connection, supports all protocols | Mail, FTP, SSH, custom ports |

## Supported Record Types

Only certain record types can be proxied:

| Record Type | Can be Proxied? | Notes |
|-------------|-----------------|-------|
| A | ✅ Yes | Most common use case |
| AAAA | ✅ Yes | IPv6 addresses |
| CNAME | ✅ Yes | Must point to proxied record |
| MX | ❌ No | Mail servers must be direct |
| TXT | ❌ No | Verification records |
| SRV | ❌ No | Service records |
| NS | ❌ No | Nameservers |

**Important:** The validation script will **reject** zone files that set `proxied: true` on unsupported record types (MX, TXT, NS, SRV, etc.). You'll get a clear error message indicating which records are invalid and must be changed to `proxied: false` or have the field removed.

## Examples

### Web Server (Proxied)
```yaml
- name: "example.com"
  type: A
  ttl: 1  # Any value is fine; automatically changed to 1 by Terraform
  values: ["203.0.113.1"]
  proxied: true  # Enable DDoS protection and CDN
```

### API Server (DNS Only)
```yaml
- name: "api"
  type: A
  ttl: 300  # This TTL value will be used as-is
  values: ["203.0.113.2"]
  proxied: false  # Direct connection for API performance
```

### Mail Server (Must be DNS Only)
```yaml
- name: "example.com"
  type: MX
  ttl: 300
  mx_records:
    - priority: 10
      value: "mail.example.com"
  # proxied field omitted or false - MX records cannot be proxied
```

### SSH Server (DNS Only)
```yaml
- name: "ssh"
  type: A
  ttl: 300
  values: ["203.0.113.3"]
  proxied: false  # SSH requires direct connection
```

## When to Use Proxied Mode

**Use `proxied: true` for:**
- Public-facing websites (HTTP/HTTPS)
- Web applications
- Static content (images, CSS, JS)
- APIs that can tolerate Cloudflare's headers
- Services on ports 80, 443, 2052, 2053, 2082, 2083, 2086, 2087, 2095, 2096, 8080, 8443, 8880

**Use `proxied: false` (or omit field) for:**
- Mail servers (MX records)
- SSH servers
- FTP servers
- Game servers
- VoIP services
- Custom applications on non-standard ports
- APIs requiring client IP addresses
- Services incompatible with Cloudflare's proxy

## TTL Behavior

When `proxied: true`:
- The TTL value in your YAML configuration is **automatically overridden to 1**
- This is required by Cloudflare's API for proxied records
- You can specify any TTL value in your YAML file (e.g., 300), but Terraform will automatically use 1 when applying
- Cloudflare controls the actual caching behavior regardless of the TTL value
- This override happens transparently - no need to update your zone files

When `proxied: false`:
- The TTL value you specify is used exactly as written
- Standard DNS TTL behavior applies
- Values typically range from 60 (1 minute) to 86400 (24 hours)

### Why TTL is 1 for Proxied Records

Cloudflare requires TTL to be set to 1 for proxied records because:
1. The actual IP address returned is Cloudflare's proxy IP, not your origin
2. Cloudflare handles caching and TTL internally
3. This allows Cloudflare to quickly update which proxy IPs are used
4. It doesn't affect actual caching behavior (Cloudflare manages this separately)

**Example:** You can keep your YAML files consistent with `ttl: 300` for all records. When a record has `proxied: true`, Terraform automatically uses `ttl: 1` when creating the record in Cloudflare.

## Migration Strategy

If you're enabling proxy for an existing zone:

1. **Test first** - Enable `proxied: true` on a subdomain to verify it works
2. **Check services** - Ensure all services work through Cloudflare's proxy
3. **Monitor** - Watch for any connection issues
4. **Gradual rollout** - Enable proxy on one record at a time
5. **Keep options** - Leave critical services (mail, SSH) in DNS-only mode

## Troubleshooting

### TTL Validation Error
If you previously encountered this error:
```
Error: error validating record @: ttl must be set to 1 when `proxied` is true
```

**This is now handled automatically.** The Terraform configuration automatically sets TTL to 1 for any record with `proxied: true`. You can keep any TTL value in your YAML files (e.g., 300) for consistency - it will be automatically overridden to 1 for proxied records.

### Connection Issues
If services stop working after enabling proxy:
1. Set `proxied: false` temporarily
2. Check Cloudflare firewall rules
3. Verify the service uses supported ports
4. Consider if the service is compatible with proxy

### Origin IP Exposure
When using `proxied: true`:
- Your origin IP is hidden from DNS queries
- Responses show Cloudflare IPs instead
- Additional security benefit

### Mixed Content Warnings
With `proxied: true` and SSL:
- Cloudflare provides free SSL certificates
- Configure SSL mode in Cloudflare dashboard
- Use "Full (Strict)" for best security

## Multi-Provider Zones

If using both Route53 and Cloudflare:

```yaml
zone_name: "example.com"
providers:
  - route53
  - cloudflare
records:
  - name: "example.com"
    type: A
    ttl: 300
    values: ["203.0.113.1"]
    proxied: true  # Only applies to Cloudflare, ignored by Route53
```

The `proxied` field is **ignored for Route53 records** - it only affects Cloudflare.

## Validation

The validation script performs the following checks:
- `proxied` must be a boolean value (`true` or `false`)
- `proxied: true` can **only** be used with A, AAAA, and CNAME record types
- If you try to set `proxied: true` on unsupported record types (MX, TXT, NS, SRV, etc.), validation will fail with a helpful error message
- **Warning (non-blocking):** If you use the `proxied` field on a zone that doesn't have Cloudflare as a provider, you'll get a warning (but validation will still pass). This helps catch configuration mistakes where the field will be ignored.

**Example validation error:**
```
❌ example.com.yml:
  - Record at index 2 (example.com, MX): Cannot set 'proxied: true' for MX records. 
    Only A, AAAA, CNAME records can be proxied through Cloudflare. 
    Remove the 'proxied' field or set it to 'false'.
```

**Example validation warning:**
```
⚠️  example.com.yml:
  - Record at index 0 (example.com, A): 'proxied' field is set but this zone does not 
    use Cloudflare as a provider. The 'proxied' field only applies to Cloudflare zones 
    and will be ignored by other providers.
```

Run validation:
```bash
python3 scripts/validate_zones.py
```

This validation happens automatically in CI/CD before any Terraform changes are applied, preventing configuration errors before they reach Cloudflare's API.

## Additional Resources

- [Cloudflare Proxy Documentation](https://developers.cloudflare.com/dns/manage-dns-records/reference/proxied-dns-records/)
- [Cloudflare Network Ports](https://developers.cloudflare.com/fundamentals/reference/network-ports/)
- [Cloudflare SSL Modes](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/)
