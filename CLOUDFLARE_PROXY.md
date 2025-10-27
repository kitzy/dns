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

**Important:** Attempting to proxy unsupported record types will cause errors during `terraform apply`.

## Examples

### Web Server (Proxied)
```yaml
- name: "example.com"
  type: A
  ttl: 300
  values: ["203.0.113.1"]
  proxied: true  # Enable DDoS protection and CDN
```

### API Server (DNS Only)
```yaml
- name: "api"
  type: A
  ttl: 300
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
- The TTL value in your configuration is **ignored**
- Cloudflare controls the TTL (typically 300 seconds)
- This is automatic and cannot be changed

When `proxied: false`:
- The TTL value you specify is used
- Standard DNS TTL behavior applies

## Migration Strategy

If you're enabling proxy for an existing zone:

1. **Test first** - Enable `proxied: true` on a subdomain to verify it works
2. **Check services** - Ensure all services work through Cloudflare's proxy
3. **Monitor** - Watch for any connection issues
4. **Gradual rollout** - Enable proxy on one record at a time
5. **Keep options** - Leave critical services (mail, SSH) in DNS-only mode

## Troubleshooting

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

The validation script checks that:
- `proxied` is a boolean value (`true` or `false`)
- No other validation is performed (Cloudflare API will reject invalid configurations)

Run validation:
```bash
python3 scripts/validate_zones.py
```

## Additional Resources

- [Cloudflare Proxy Documentation](https://developers.cloudflare.com/dns/manage-dns-records/reference/proxied-dns-records/)
- [Cloudflare Network Ports](https://developers.cloudflare.com/fundamentals/reference/network-ports/)
- [Cloudflare SSL Modes](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/)
