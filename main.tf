# Fetch DNS zone details from combined YAML file
locals {
  dns_zones = yamldecode(file("${path.module}/combined_zones.yml"))
}

# Fetch existing Route 53 Zones
data "aws_route53_zone" "selected" {
  for_each = { for zone in local.dns_zones : zone.zone_name => zone }
  name     = each.value.zone_name
}

# Fetch existing Route 53 records
data "aws_route53_records" "existing" {
  for_each = data.aws_route53_zone.selected
  zone_id  = each.value.zone_id
}

# Create DNS records if they don't already exist
resource "aws_route53_record" "dns_records" {
  for_each = { for zone in local.dns_zones : zone.zone_name => zone }

  zone_id = data.aws_route53_zone.selected[each.key].zone_id
  name    = each.value.records[0].name
  type    = each.value.records[0].type
  ttl     = each.value.records[0].ttl
  records = each.value.records[0].values

  lifecycle {
    ignore_changes = [ttl, records]
  }
}