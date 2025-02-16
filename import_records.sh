#!/bin/bash
set -e

# Directory containing your YAML files
DNS_ZONES_DIR="dns_zones"

# Loop through each YAML file in the dns_zones directory
for zone_file in "$DNS_ZONES_DIR"/*.yml; do
  if [ -f "$zone_file" ]; then
    # Read the zone_name from the YAML file using yq
    DOMAIN_NAME=$(yq eval '.zone_name' "$zone_file")
    echo "Processing domain: $DOMAIN_NAME"

    # Dynamically fetch the hosted zone ID for the domain name
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${DOMAIN_NAME}.'].Id" --output text)

    if [ "$HOSTED_ZONE_ID" == "None" ]; then
      echo "Error: Hosted Zone for $DOMAIN_NAME not found!"
      continue
    fi

    # Remove the '/hostedzone/' prefix from the Hosted Zone ID
    HOSTED_ZONE_ID=$(echo "$HOSTED_ZONE_ID" | sed 's#/hostedzone/##')

    echo "Fetching existing Route 53 records for Hosted Zone ID: $HOSTED_ZONE_ID..."

    # Fetch the current records in the hosted zone
    aws route53 list-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" | jq -c '.ResourceRecordSets[]' | while read -r record; do
      NAME=$(echo "$record" | jq -r '.Name')
      TYPE=$(echo "$record" | jq -r '.Type')

      # Terraform import format: terraform import aws_route53_record.<RESOURCE_NAME> <ZONE_ID>_<RECORD_NAME>_<RECORD_TYPE>
      RESOURCE_NAME=$(echo "$NAME" | tr -d '.' | tr -d '*' | tr '[:upper:]' '[:lower:]')_$TYPE
      IMPORT_CMD="terraform import aws_route53_record.${RESOURCE_NAME} ${HOSTED_ZONE_ID}_${NAME}_${TYPE}"

      echo "Importing: $IMPORT_CMD"
      $IMPORT_CMD || echo "Failed to import $NAME ($TYPE), skipping..."
    done

    echo "Route 53 record import completed for $DOMAIN_NAME."
  fi
done
