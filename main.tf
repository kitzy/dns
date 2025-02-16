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

  # Group records by zone name to handle multiple zones with the same name
  grouped_dns_zones = { for zone in local.dns_zones : zone.zone_name => [
    for record in local.dns_zones : 
    record if record.zone_name == zone.zone_name
  ]}
}

# Dynamically fetch each Route 53 zone based on the zone name from the YAML files
data "aws_route53_zone" "dns_zone" {
  for_each = local.grouped_dns_zones

  name = each.key
}

output "zone_ids" {
  value = { for k, v in data.aws_route53_zone.dns_zone : k => v.id }
}

# Generate resources for each DNS record defined, based on zone and record name
resource "aws_route53_record" "dns_records" {
  for_each = {
    for record in local.dns_zones : "${record.zone_name}_${record.name}_${record.type}" => record
  }

  zone_id = data.aws_route53_zone.dns_zone[each.value.zone_name].id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.values
}
