#!/bin/bash
set -e  # Exit on error

echo "Starting Route 53 record import..."

for zone_file in $(find "$(dirname "$0")/dns_zones" -name "*.yml"); do
  zone_name=$(basename "$zone_file" .yml)
  zone_id=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='$zone_name.'].Id" --output text | tr -d '[:space:]')

  if [ -z "$zone_id" ]; then
    echo "No hosted zone found for $zone_name, skipping..."
    continue
  fi

  jq -r '.records[] | "\(.name) \(.type)"' "$zone_file" | while read -r record_name record_type; do
    formatted_record_name=$(echo "$record_name" | sed 's/\*/*/g')

    import_command="terraform import aws_route53_record.record_${zone_name}_${record_name}_${record_type} ${zone_id}_${formatted_record_name}_${record_type}"
    echo "Running: $import_command"
    eval "$import_command"
  done
done

echo "Route 53 record import completed."
