#!/usr/bin/env python3
import os
import yaml
import boto3

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DNS_ZONES_DIR = os.path.join(REPO_ROOT, "dns_zones")

route53 = boto3.client("route53")

def load_defined_records(zone_data, zone_name):
    records = set()
    for rec in zone_data.get("records", []):
        rtype = rec["type"].upper()
        if rtype in ("NS", "SOA"):
            continue
        name = rec["name"]
        fqdn = name if name == zone_name or name.endswith("." + zone_name) else f"{name}.{zone_name}"
        set_id = rec.get("set_identifier")
        records.add((fqdn, rtype, set_id))
    return records

for filename in os.listdir(DNS_ZONES_DIR):
    if not filename.endswith(".yml"):
        continue
    path = os.path.join(DNS_ZONES_DIR, filename)
    with open(path, "r") as f:
        zone_data = yaml.safe_load(f)
    zone_name = zone_data["zone_name"]
    defined = load_defined_records(zone_data, zone_name)

    resp = route53.list_hosted_zones_by_name(DNSName=zone_name)
    hosted_zone = next((z for z in resp["HostedZones"] if z["Name"].rstrip(".") == zone_name), None)
    if hosted_zone is None:
        continue
    zone_id = hosted_zone["Id"].split("/")[-1]

    paginator = route53.get_paginator("list_resource_record_sets")
    for page in paginator.paginate(HostedZoneId=zone_id):
        for record in page["ResourceRecordSets"]:
            rtype = record["Type"]
            if rtype in ("NS", "SOA"):
                continue
            name = record["Name"].rstrip(".").replace("\\052", "*")
            set_id = record.get("SetIdentifier")
            key = (name, rtype, set_id)
            if key not in defined:
                print(f"Deleting {name} {rtype}")
                route53.change_resource_record_sets(
                    HostedZoneId=zone_id,
                    ChangeBatch={
                        "Changes": [
                            {"Action": "DELETE", "ResourceRecordSet": record}
                        ]
                    },
                )
