provider "aws" {
  region = "us-east-1"
}

# Read all the YAML files in the dns_zones directory and decode them
locals {
  # Original dns_zones from all YAML files in the dns_zones directory
  dns_zones_input = flatten([
    for zone_file in fileset("dns_zones/", "*.yml") : 
      yamldecode(file("dns_zones/${zone_file}"))
  ])

  # Flatten the dns_zones structure into a more usable format for Route 53 records
  dns_zones = flatten([
    for zone_data in local.dns_zones_input : [
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

# Fetch existing records from Route 53
data "aws_route53_zone" "dns_zone" {
  name = "<zone-name>"
}

output "zone_id" {
  value = data.aws_route53_zone.dns_zone.id
}

# Generate resources for each DNS record defined
resource "aws_route53_record" "dns_records" {
  for_each = {
    for record in local.dns_zones : "${record.zone_name}_${record.name}_${record.type}" => record
  }

  zone_id = data.aws_route53_zone.dns_zone.id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.values
}
