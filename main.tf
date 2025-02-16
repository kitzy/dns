provider "aws" {
  region = "us-east-1"
}

# Get all YAML files from the dns_zones directory
locals {
  zone_files = [for f in fileset("${path.module}/dns_zones", "*.yml") : "${path.module}/dns_zones/${f}"]
}

# Decode each YAML file into a usable format
locals {
  dns_zones = {
    for file in local.zone_files :
    basename(file, ".yml") => yamldecode(file(file))
  }
}

# Create Route 53 zones for each zone
resource "aws_route53_zone" "zones" {
  for_each = local.dns_zones

  name = each.value["zone_name"]
}

# Create Route 53 records for each zone
resource "aws_route53_record" "records" {
  for_each = {
    for zone_key, zone_data in local.dns_zones :
    for record in zone_data["records"] :
    "${zone_key}_${record["name"]}_${record["type"]}" => record
  }

  zone_id = aws_route53_zone.zones[each.value["zone_name"]].id
  name    = each.value["name"]
  type    = each.value["type"]
  ttl     = each.value["ttl"]
  records = each.value["values"]
}
