provider "aws" {
  region = "us-east-1"
}

# Get all YAML files from the dns_zones directory
locals {
  zone_files = [for f in fileset("${path.module}/dns_zones", "*.yml") : "${path.module}/dns_zones/${f}"]
}

# Decode each YAML file into a usable format
locals {
  # Parse the YAML file (which should be in a format that defines multiple zones)
  dns_zones = yamldecode(file("zones.yaml"))
}

resource "aws_route53_zone" "zones" {
  for_each = { for zone in local.dns_zones : zone["zone_name"] => zone }

  name = each.value["zone_name"]
}

resource "aws_route53_record" "dns_records" {
  for_each = {
    for zone_key, zone_data in local.dns_zones :
    for record in zone_data["records"] :
    "${zone_key}_${record["name"]}_${record["type"]}" => record
  }

  zone_id = aws_route53_zone.dns_zones[each.key].zone_id
  name    = each.value["name"]
  type    = each.value["type"]
  ttl     = each.value["ttl"]
  records = each.value["values"]
}
