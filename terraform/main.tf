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

  # Separate zones by provider
  route53_zones = {
    for zname, z in local.zones :
    zname => z if try(z.provider, "route53") == "route53"
  }

  cloudflare_zones = {
    for zname, z in local.zones :
    zname => z if try(z.provider, "route53") == "cloudflare"
  }
  # Route53 records
  route53_records = flatten([
    for zname, z in local.route53_zones : [
      for r in z.records : {
        zone_name      = zname
        name           = r.name
        type           = r.type
        ttl            = r.ttl
        values         = r.values
        set_identifier = try(r.set_identifier, null)
        routing_policy = try(r.routing_policy, null)
      } if upper(r.type) != "NS" && upper(r.type) != "SOA"
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
        values    = r.values
      } if upper(r.type) != "NS" && upper(r.type) != "SOA"
    ]
  ])
  route53_record_map = {
    for r in local.route53_records : "${r.zone_name}_${r.name}_${r.type}${r.set_identifier != null ? "_${r.set_identifier}" : ""}" => r
  }

  # Flatten Cloudflare records to handle multiple values
  cloudflare_record_map = {
    for idx, r in flatten([
      for record in local.cloudflare_records : [
        for value_idx, value in record.values : {
          zone_name = record.zone_name
          name      = record.name
          type      = record.type
          ttl       = record.ttl
          value     = value
          key       = "${record.zone_name}_${record.name}_${record.type}_${value_idx}"
        }
      ]
    ]) : r.key => r
  }
}

resource "aws_route53_zone" "this" {
  for_each      = local.route53_zones
  name          = each.value.zone_name
  comment       = "Managed by Terraform"
  force_destroy = true
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

  zone_id = cloudflare_zone.this[each.value.zone_name].id
  name    = each.value.name == each.value.zone_name ? "@" : each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  content = each.value.value
}
