provider "aws" {
  region = "us-east-1"
}

# Read all YAML files in the dns_zones/ directory
data "local_file" "dns_configs" {
  for_each = fileset("${path.module}/dns_zones", "*.yaml")
  filename = "${path.module}/dns_zones/${each.value}"
}

# Decode YAML content
locals {
  zones = { for file, content in data.local_file.dns_configs : file => yamldecode(content.content) }
}

# Create Route 53 Hosted Zones if they don't exist
resource "aws_route53_zone" "zones" {
  for_each = local.zones
  name     = each.value.zone_name
  private_zone = false
  tags = {
    "Name" = each.value.zone_name
  }
}

# Create DNS Records in the respective Zone
resource "aws_route53_record" "records" {
  for_each = merge([for file, zone in local.zones : { for rec in zone.records :
    "${rec.name}.${zone.zone_name}_${rec.type}" => merge(rec, { zone_name = zone.zone_name }) }]...)

  zone_id = aws_route53_zone.zones[each.value.zone_name].zone_id
  name    = "${each.value.name}.${each.value.zone_name}"
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.values

  lifecycle {
    create_before_destroy = true
  }
}
