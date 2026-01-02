terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
  cloud {
    organization = "kitzy_net"
    workspaces {
      name = "dns"
    }
  }
}

provider "aws" {
  region = var.AWS_REGION
}

provider "cloudflare" {
  api_token = var.CLOUDFLARE_API_TOKEN
}

locals {
  zone_files = fileset("${path.module}/../dns_zones", "*.yml")
  zones = {
    for file in local.zone_files :
    yamldecode(file("${path.module}/../dns_zones/${file}")).zone_name =>
    yamldecode(file("${path.module}/../dns_zones/${file}"))
  }

  # Load global tunnel definitions
  tunnels_file = "${path.module}/../cloudflare_tunnels.yml"
  global_tunnels = try(
    yamldecode(file(local.tunnels_file)).tunnels,
    {}
  )

  # Helper function to get providers for a zone (supports both single and multi-provider formats)
  zone_providers = {
    for zname, z in local.zones :
    zname => (
      # Multi-provider format
      can(z.providers) ? z.providers :
      # Single provider format (with route53 default)
      [try(z.provider, "route53")]
    )
  }

  # Separate zones by provider (zones can appear in multiple provider maps)
  route53_zones = {
    for zname, z in local.zones :
    zname => z if contains(local.zone_providers[zname], "route53")
  }

  cloudflare_zones = {
    for zname, z in local.zones :
    zname => z if contains(local.zone_providers[zname], "cloudflare")
  }

  # Extract nameservers from NS records for registered domain management
  # If NS records are present for the apex, assume domain is registered via AWS
  domain_nameservers = {
    for zname, z in local.route53_zones : zname => distinct(flatten([
      for r in z.records :
      r.values if upper(r.type) == "NS" && r.name == zname
      ])) if length(flatten([
      for r in z.records :
      r.values if upper(r.type) == "NS" && r.name == zname
    ])) > 0
  }

  # Route53 records
  route53_records = flatten([
    for zname, z in local.route53_zones : [
      for r in z.records : {
        zone_name = zname
        name      = r.name
        type      = r.type
        ttl       = r.ttl
        values = upper(r.type) == "MX" && can(r.mx_records) ? [
          for mx in r.mx_records : "${mx.priority} ${mx.value}"
        ] : try(r.values, [])
        set_identifier = try(r.set_identifier, null)
        routing_policy = try(r.routing_policy, null)
      } if upper(r.type) != "NS" && upper(r.type) != "SOA" && upper(r.type) != "TUNNEL" # Exclude NS, SOA, and TUNNEL
    ]
  ])

  # Cloudflare records (only simple routing supported)
  cloudflare_records = flatten([
    for zname, z in local.cloudflare_zones : [
      for r in z.records : {
        zone_name = zname
        name      = r.name
        type      = r.type
        ttl       = r.ttl
        values = upper(r.type) == "MX" && can(r.mx_records) ? [
          for mx in r.mx_records : "${mx.priority} ${mx.value}"
        ] : try(r.values, [])
        proxied = try(r.proxied, false)                                                 # Default to DNS only (false) if not specified
      } if upper(r.type) != "NS" && upper(r.type) != "SOA" && upper(r.type) != "TUNNEL" # Exclude NS, SOA, and TUNNEL
    ]
  ])

  # Extract tunnel definitions - merge global tunnels with zone-specific tunnels
  # Zone-specific tunnels take precedence over global ones (if same name)
  tunnel_definitions = flatten([
    for zname, z in local.cloudflare_zones : [
      for tunnel_name, tunnel_config in merge(local.global_tunnels, try(z.tunnels, {})) : {
        zone_name   = zname
        tunnel_name = tunnel_name
        tunnel_id   = tunnel_config.tunnel_id
      }
    ]
  ])

  # Map tunnel names to their IDs for lookup (scoped by zone)
  tunnel_id_map = {
    for t in local.tunnel_definitions :
    "${t.zone_name}:${t.tunnel_name}" => t.tunnel_id
  }

  # Extract tunnel records (TUNNEL type)
  tunnel_records = flatten([
    for zname, z in local.cloudflare_zones : [
      for r in z.records : {
        zone_name   = zname
        hostname    = r.name == zname ? zname : "${r.name}.${zname}"
        tunnel_name = r.tunnel.name
        tunnel_id   = local.tunnel_id_map["${zname}:${r.tunnel.name}"]
        service     = r.tunnel.service
      } if upper(r.type) == "TUNNEL"
    ]
  ])

  # Create map for tunnel config resources
  tunnel_config_map = {
    for t in local.tunnel_records :
    "${t.zone_name}_${t.hostname}" => t
  }
  route53_record_map = {
    for r in local.route53_records : "${r.zone_name}_${r.name}_${r.type}${r.set_identifier != null ? "_${r.set_identifier}" : ""}" => r
  }

  # Flatten Cloudflare records to handle multiple values
  cloudflare_record_map = {
    for r in flatten([
      for record in local.cloudflare_records : [
        for value_idx, value in record.values : {
          zone_name = record.zone_name
          name      = record.name
          type      = record.type
          ttl       = record.proxied ? 1 : record.ttl # Cloudflare requires TTL=1 for proxied records
          content   = upper(record.type) == "MX" ? split(" ", value)[1] : (upper(record.type) == "TXT" ? "\"${value}\"" : value)
          priority  = upper(record.type) == "MX" ? tonumber(split(" ", value)[0]) : null
          proxied   = record.proxied
          key       = "${record.zone_name}_${record.name}_${record.type}_${value_idx}"
        }
      ]
    ]) : r.key => r
  }
}

# AWS Route53 Zones
resource "aws_route53_zone" "this" {
  for_each      = local.route53_zones
  name          = each.value.zone_name
  comment       = "Managed by Terraform"
  force_destroy = true
}

# AWS Route53 Domain Registrations - Update nameservers at registrar level
resource "aws_route53domains_registered_domain" "this" {
  for_each = local.domain_nameservers

  domain_name = each.key

  dynamic "name_server" {
    for_each = each.value
    content {
      name = name_server.value
    }
  }

  # Prevent automatic renewal changes and other registrar settings from being managed
  lifecycle {
    ignore_changes = [
      admin_contact,
      registrant_contact,
      tech_contact,
      auto_renew,
      transfer_lock,
      admin_privacy,
      registrant_privacy,
      tech_privacy,
    ]
  }
}

resource "aws_route53_record" "this" {
  for_each = local.route53_record_map

  zone_id        = aws_route53_zone.this[each.value.zone_name].zone_id
  name           = each.value.name == each.value.zone_name ? each.value.name : "${each.value.name}.${each.value.zone_name}"
  type           = each.value.type
  ttl            = each.value.ttl
  records        = each.value.values
  set_identifier = each.value.set_identifier

  dynamic "weighted_routing_policy" {
    for_each = each.value.routing_policy != null && try(each.value.routing_policy.type, "") == "weighted" ? [each.value.routing_policy] : []
    content {
      weight = each.value.routing_policy.weight
    }
  }

  dynamic "latency_routing_policy" {
    for_each = each.value.routing_policy != null && try(each.value.routing_policy.type, "") == "latency" ? [each.value.routing_policy] : []
    content {
      region = each.value.routing_policy.region
    }
  }

  dynamic "geolocation_routing_policy" {
    for_each = each.value.routing_policy != null && try(each.value.routing_policy.type, "") == "geolocation" ? [each.value.routing_policy] : []
    content {
      continent   = try(each.value.routing_policy.continent, null)
      country     = try(each.value.routing_policy.country, null)
      subdivision = try(each.value.routing_policy.subdivision, null)
    }
  }

  dynamic "failover_routing_policy" {
    for_each = each.value.routing_policy != null && try(each.value.routing_policy.type, "") == "failover" ? [each.value.routing_policy] : []
    content {
      type = each.value.routing_policy.role
    }
  }

  multivalue_answer_routing_policy = each.value.routing_policy != null && try(each.value.routing_policy.type, "") == "multivalue" ? true : null
}

# Cloudflare Zone Resources
resource "cloudflare_zone" "this" {
  for_each   = local.cloudflare_zones
  zone       = each.value.zone_name
  account_id = var.CLOUDFLARE_ACCOUNT_ID
}

# Cloudflare Record Resources (simple routing only)
resource "cloudflare_record" "this" {
  for_each = local.cloudflare_record_map

  zone_id  = cloudflare_zone.this[each.value.zone_name].id
  name     = each.value.name == each.value.zone_name ? "@" : each.value.name
  type     = each.value.type
  ttl      = each.value.ttl
  content  = each.value.content
  priority = each.value.priority
  proxied  = each.value.proxied
}

# Cloudflare Tunnel Configuration Resources
# Note: This manages the tunnel routing configuration (hostname -> service mapping)
# The actual tunnel must already exist in Cloudflare (created via cloudflared or dashboard)
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  for_each   = local.tunnel_config_map
  account_id = var.CLOUDFLARE_ACCOUNT_ID
  tunnel_id  = each.value.tunnel_id

  config {
    ingress_rule {
      hostname = each.value.hostname
      service  = each.value.service
    }

    # Required catch-all rule for traffic that doesn't match any hostname
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Create CNAME records for tunnel hostnames
resource "cloudflare_record" "tunnel" {
  for_each = local.tunnel_config_map

  zone_id = cloudflare_zone.this[each.value.zone_name].id
  name    = each.value.hostname == each.value.zone_name ? "@" : split(".${each.value.zone_name}", each.value.hostname)[0]
  type    = "CNAME"
  content = "${each.value.tunnel_id}.cfargotunnel.com"
  ttl     = 1
  proxied = true

  depends_on = [cloudflare_zero_trust_tunnel_cloudflared_config.this]
}

# Output nameservers for Route53 zones
output "route53_nameservers" {
  description = "Route53 zone nameservers (AWS-assigned)"
  value = {
    for zname, zone in aws_route53_zone.this :
    zname => zone.name_servers
  }
}

# Output domain registrar nameservers being managed
output "domain_registrar_nameservers" {
  description = "Nameservers configured at the domain registrar level (Route53 Domains)"
  value       = local.domain_nameservers
}

# Output Cloudflare nameservers
output "cloudflare_nameservers" {
  description = "Cloudflare zone nameservers"
  value = {
    for zname, zone in cloudflare_zone.this :
    zname => zone.name_servers
  }
}

# Output tunnel configurations
output "tunnel_configurations" {
  description = "Cloudflare tunnel hostname mappings"
  value = {
    for k, v in local.tunnel_config_map :
    k => {
      hostname    = v.hostname
      tunnel_name = v.tunnel_name
      tunnel_id   = v.tunnel_id
      service     = v.service
    }
  }
}