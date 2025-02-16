#!/bin/bash

# Get the list of YAML files
FILES=$(find ./dns_zones -name "*.yml")

for FILE in $FILES; do
  echo "Starting Route 53 record import..."

  # Extract the domain name from the YAML file using yq
  DOMAIN=$(yq e '.zone_name' "$FILE")
  
  # Debugging line to show what DOMAIN was extracted
  echo "Extracted zone name: $DOMAIN"
  
  if [ -z "$DOMAIN" ]; then
    echo "Error: Domain name is empty. Skipping file $FILE."
    continue
  fi

  # Get the hosted zone ID for the domain
  ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN" --query "HostedZones[0].Id" --output text)

  if [[ "$ZONE_ID" == "None" ]]; then
    echo "Zone ID for $DOMAIN not found. Skipping..."
    continue
  fi

  # Read records from the YAML file and import them one by one
  yq e '.records[]' "$FILE" | while read -r record; do
    NAME=$(echo "$record" | yq e '.name' -)
    TYPE=$(echo "$record" | yq e '.type' -)
    TTL=$(echo "$record" | yq e '.ttl' -)
    VALUES=$(echo "$record" | yq e '.values // empty' -)

    # Skip this record if no values are provided
    if [ -z "$VALUES" ]; then
      echo "Skipping record $NAME ($TYPE) because it has no values."
      continue
    fi

    # Join the values into a comma-separated string
    VALUES=$(echo "$VALUES" | sed 's/\[//g; s/\]//g; s/ /,/g')

    # Replace "@" with the domain name
    if [[ "$NAME" == "@" ]]; then
      NAME="$DOMAIN"
    fi

    # Import the record
    echo "Importing: terraform import aws_route53_record.${DOMAIN}_${NAME}_${TYPE} ${ZONE_ID}_$NAME_$TYPE"
    terraform import aws_route53_record.${DOMAIN}_${NAME}_${TYPE} ${ZONE_ID}_$NAME_$TYPE || echo "Failed to import $NAME ($TYPE), skipping..."
  done

  echo "Route 53 record import completed."
done
