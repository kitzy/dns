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

  count = length([
    for r in each.value.records :
    r if !contains([
      for existing in data.aws_route53_records.existing[each.key].records : existing.name
    ], r.name)
  ])
}

# Fetch the hosted zone ID of each zone from DNS zone files and write to zone_ids.json
run "Fetching hosted zone IDs" {
  echo "ZONE_IDS={}" > zone_ids.json  # Initialize an empty JSON object
  for file in ./dns_zones/*.yml; do
    zone_name=$(yq e '.zone_name' "$file")
    zone_id=$(aws route53 list-hosted-zones-by-name --dns-name "$zone_name" --query "HostedZones[0].Id" --output text | sed 's|/hostedzone/||')
    echo "Fetching hosted zone ID for $zone_name: $zone_id"
    yq e ". + {\"$zone_name\": \"$zone_id\"}" -i zone_ids.json
  done
}

# Fetch existing records from the Route53 hosted zones
data "aws_route53_records" "existing" {
  for_each = data.aws_route53_zone.selected
  zone_id  = each.value.zone_id
}