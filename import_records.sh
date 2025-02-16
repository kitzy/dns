#!/bin/bash
set -e

HOSTED_ZONE_ID="YOUR_ZONE_ID"

echo "Fetching existing Route 53 records..."
aws route53 list-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" | jq -c '.ResourceRecordSets[]' | while read -r record; do
  NAME=$(echo "$record" | jq -r '.Name')
  TYPE=$(echo "$record" | jq -r '.Type')

  # Terraform import format: terraform import aws_route53_record.<RESOURCE_NAME> <ZONE_ID>_<RECORD_NAME>_<RECORD_TYPE>
  RESOURCE_NAME=$(echo "$NAME" | tr -d '.' | tr -d '*' | tr '[:upper:]' '[:lower:]')_$TYPE
  IMPORT_CMD="terraform import aws_route53_record.${RESOURCE_NAME} ${HOSTED_ZONE_ID}_${NAME}_${TYPE}"

  echo "Importing: $IMPORT_CMD"
  $IMPORT_CMD || echo "Failed to import $NAME ($TYPE), skipping..."
done

echo "Route 53 record import completed."
