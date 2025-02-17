locals {
  dns_zones = yamldecode(file("combined_dns_zones.yaml")).zones
}

resource "aws_route53_record" "dns_records" {
  for_each = { for zone in local.dns_zones : 
    for record in zone.records : 
      "${zone.zone_name}_${record.name}_${record.type}" => record if
      !(record.name in [for existing_record in data.aws_route53_records.existing_records[zone.zone_name].records : existing_record.name])
  }

  zone_id = data.aws_route53_zone.dns_zone[each.value.zone_name].id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.values
}
