#!/bin/bash

echo "Starting Route 53 record import..."

# Loop through each YAML file in the dns_zones directory
for file in dns_zones/*.yml; do
  # Extract the domain name from the zone file
  zone_name=$(yq e '.zone_name' "$file")
  echo "Processing zone: $zone_name"

  # Get the Route 53 hosted zone ID (assuming this is done outside the loop, adjust as necessary)
  zone_id=$(aws route53 list-hosted-zones-by-name --dns-name "$zone_name" --query "HostedZones[0].Id" --output text)
  
  if [[ "$zone_id" == "None" ]]; then
    echo "Error: Zone ID not found for $zone_name"
    continue
  fi

  # Loop through each record in the YAML file and import it
  records=$(yq e '.records[]' "$file")
  
  for record in $records; do
    # Extract record details from YAML
    record_name=$(echo $record | jq -r .name)
    record_type=$(echo $record | jq -r .type)
    record_value=$(echo $record | jq -r .value)
    
    # Generate a Terraform configuration block for this record
    cat <<EOF >> route53_import.tf
resource "aws_route53_record" "${zone_name}_${record_name}_${record_type}" {
  zone_id = "$zone_id"
  name    = "$record_name"
  type    = "$record_type"
  ttl     = 300
  records = ["$record_value"]
}
EOF

    # Now import the record using the generated Terraform configuration
    terraform import aws_route53_record.${zone_name}_${record_name}_${record_type} "${zone_id}_${record_name}"
    
  done
done

echo "Route 53 record import completed."
