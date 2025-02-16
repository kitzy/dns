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

data "aws_route53_records" "existing_records" {
  zone_id = data.aws_route53_zone.dns_zone.id
}

# Update your dns_zones variable to include only records that need to be created
locals {
  # Flatten the DNS records
  new_records = flatten([
    for zone_data in local.dns_zones : [
      for record in zone_data["records"] : {
        zone_name = zone_data["zone_name"]
        name      = record["name"]
        type      = record["type"]
        ttl       = record["ttl"]
        values    = record["values"]
      }
    ]
  ])

  # Extract the existing records and compare them
  existing_record_names = flatten([for record in data.aws_route53_records.existing_records.records : record.name])

  # Only include records that are not already in the existing records
  records_to_create = [
    for r in local.new_records : 
    r if !(r["name"] in local.existing_record_names)
  ]
}

resource "aws_route53_record" "dns_records" {
  for_each = { for record in local.records_to_create : "${record.zone_name}_${record.name}_${record.type}" => record }

  zone_id = data.aws_route53_zone.dns_zone.id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.values
}
