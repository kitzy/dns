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
        ] : r.values
        set_identifier = try(r.set_identifier, null)
        routing_policy = try(r.routing_policy, null)
      } if upper(r.type) != "NS" && upper(r.type) != "SOA" # Exclude NS and SOA - auto-managed
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
        ] : r.values
        proxied = try(r.proxied, false) # Default to DNS only (false) if not specified
      } if upper(r.type) != "NS" && upper(r.type) != "SOA" # Exclude NS and SOA - auto-managed
    ]
  ])
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