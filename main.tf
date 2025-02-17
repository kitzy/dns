terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  dns_zones = yamldecode(file("${path.module}/combined_zones.yml"))
}

# Load YAML file containing all DNS zones and records
locals {
  zone_ids = jsondecode(file("${path.module}/zone_ids.json"))
}

locals {
  existing_records = {
    for zone_name, zone_id in local.zone_ids :
    zone_name => jsondecode(file("${path.module}/existing_records_${zone_name}.json"))
  }
}

locals {
  existing_record_names = {
    for zone_name, records in local.existing_records :
    zone_name => [for r in records.ResourceRecordSets : r.Name]
  }
}


# Fetch Route 53 Hosted Zones dynamically
data "aws_route53_zone" "selected" {
  for_each = { for zone in local.dns_zones : zone.zone_name => zone }
  name     = each.value.zone_name
}

# Fetch existing records in each zone
data "aws_route53_records" "existing" {
  for_each = data.aws_route53_zone.selected
  zone_id  = each.value.zone_id
}

# Create Route 53 records, skipping existing ones
resource "aws_route53_record" "dns_records" {
  for_each = {
    for r in flatten([
      for zone in local.dns_zones : [
        for record in zone.records : {
          key       = "${zone.zone_name}_${record.name}_${record.type}"
          zone_name = zone.zone_name
          name      = record.name
          type      = record.type
          ttl       = record.ttl
          values    = record.values
        }
      ]
    ]) : r.key => r
    if !contains(local.existing_record_names[r.zone_name], r.name)
  }

  zone_id = local.zone_ids[each.value.zone_name]
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.values
}
