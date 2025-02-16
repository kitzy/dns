# Provider setup
provider "aws" {
  region = "us-east-1"  # Adjust this to your AWS region
}

# Read all YAML files in the dns_zones directory
locals {
  dns_zones_files = [for file in fileset("${path.module}/dns_zones", "*.yaml") : "${path.module}/dns_zones/${file}"]
  dns_zones = {
    for file in local.dns_zones_files : 
    file => yamldecode(file(file))
  }
}

# Create Route 53 Zones if they don't exist
resource "aws_route53_zone" "dns_zones" {
  for_each = local.dns_zones

  name = each.value["zone_name"]

  # This ensures that Route 53 is only created if it does not exist
}

# Create Route 53 Records for each zone
locals {
  dns_zones = flatten([
    for zone_file, zone_data in local.dns_zones : [
      for record in zone_data["records"] : {
        zone_name = zone_data["zone_name"]
        name      = record["name"]
        type      = record["type"]
        ttl       = record["ttl"]
        values    = record["values"]
      }
    ]
  ])
}

resource "aws_route53_record" "dns_records" {
  for_each = {
    for record in local.dns_zones :
    "${record["zone_name"]}_${record["name"]}_${record["type"]}" => record
  }

  zone_id = data.aws_route53_zone.selected[each.value.zone_name].id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.values
}



