# Provider Configuration
provider "aws" {
  region = "us-east-1"
}

# Load DNS zones from the combined YAML file
locals {
  dns_zones = yamldecode(file("${path.module}/combined_zones.yml"))
}

# Data source to get existing DNS records in Route 53
data "aws_route53_zone" "dns_zone" {
  for_each = { for zone in local.dns_zones : zone.zone_name => zone }
  name     = each.key
}

data "aws_route53_records" "existing_records" {
  for_each = data.aws_route53_zone.dns_zone
  zone_id  = each.value.id
}

# Manage DNS records
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
  }

  zone_id = data.aws_route53_zone.selected[each.value.zone_name].zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.values
}
