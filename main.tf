provider "aws" {
  region = "us-east-1"
}

# Read all YAML files in the dns_zones/ directory
data "local_file" "dns_configs" {
  for_each = fileset("${path.module}/dns_zones", "*.yml")
  filename = "${path.module}/dns_zones/${each.value}"
}

# Decode YAML content properly
locals {
  zones = { for file, content in data.local_file.dns_configs :
    yamldecode(content.content).zone_name => yamldecode(content.content)
  }
}

# Lookup existing Route 53 zones
data "aws_route53_zone" "existing" {
  for_each = local.zones
  name     = each.key
}

# Create Route 53 Hosted Zones only if they don't exist
resource "aws_route53_zone" "zones" {
  for_each = { for name, zone in local.zones : name => zone if length(data.aws_route53_zone.existing[name].zone_id) == 0 }

  name = each.value.zone_name
  tags = {
    "Name" = each.value.zone_name
  }
}

# Merge existing and new zones
locals {
  final_zones = merge(
    { for name, zone in local.zones : name => merge(zone, { zone_id = data.aws_route53_zone.existing[name].zone_id }) },
    { for name, zone in aws_route53_zone.zones : name => merge(zone, { zone_id = zone.zone_id }) }
  )
}

# Fetch existing Route 53 records for each zone
data "aws_route53_record" "existing_records" {
  for_each = merge(flatten([
    for zone_name, zone in local.final_zones : [
      for rec in zone.records : {
        key       = "${rec.name}.${zone_name}_${rec.type}"
        zone_id   = zone.zone_id
        name      = "${rec.name}.${zone_name}"
        type      = rec.type
      }
    ]
  ])...)

  zone_id = each.value.zone_id
  name    = each.value.name
  type    = each.value.type
}

# Create Route 53 DNS Records (import existing and create new ones)
resource "aws_route53_record" "records" {
  for_each = merge(flatten([
    for zone_name, zone in local.final_zones : [
      for rec in zone.records : {
        key       = "${rec.name}.${zone_name}_${rec.type}"
        zone_id   = zone.zone_id
        name      = "${rec.name}.${zone_name}"
        type      = rec.type
        ttl       = rec.ttl
        values    = rec.values
      }
    ]
  ])...)

  zone_id = each.value.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.values

  lifecycle {
    create_before_destroy = true
  }
}
