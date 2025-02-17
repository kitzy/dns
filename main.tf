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

# Load YAML file containing all DNS zones and records
locals {
  dns_zones = yamldecode(file("${path.module}/combined_zones.yml"))
}

# Fetch Route 53 Hosted Zones dynamically
data "aws_route53_zone" "selected" {
  for_each = { for zone in local.dns_zones : zone.zone_name => zone }
  name     = each.key
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
    if !contains([for existing in data.aws_route53_records.existing[r.zone_name].records : existing.name], r.name)
  }

  zone_id = data.aws_route53_zone.selected[each.value.zone_name].zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.values
}
