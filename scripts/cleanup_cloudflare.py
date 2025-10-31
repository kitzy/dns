#!/usr/bin/env python3
import os
import yaml
import requests
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DNS_ZONES_DIR = os.path.join(REPO_ROOT, "dns_zones")

# Get Cloudflare API credentials from environment
CLOUDFLARE_API_TOKEN = os.environ.get("CLOUDFLARE_API_TOKEN")
if not CLOUDFLARE_API_TOKEN:
    print("Error: CLOUDFLARE_API_TOKEN environment variable not set", file=sys.stderr)
    sys.exit(1)

HEADERS = {
    "Authorization": f"Bearer {CLOUDFLARE_API_TOKEN}",
    "Content-Type": "application/json",
}
BASE_URL = "https://api.cloudflare.com/client/v4"


def load_defined_records(zone_data, zone_name):
    """Load all defined records from the YAML configuration."""
    records = set()
    for rec in zone_data.get("records", []):
        rtype = rec["type"].upper()
        if rtype in ("NS", "SOA"):
            continue
        
        name = rec["name"]
        # Normalize FQDN
        if name == zone_name or name.endswith("." + zone_name):
            fqdn = name
        else:
            fqdn = f"{name}.{zone_name}"
        
        # Handle different record types
        if rtype == "MX":
            # For MX records, we track each priority/value pair
            for mx in rec.get("mx_records", []):
                records.add((fqdn, rtype, mx["priority"], mx["value"]))
        else:
            # For other record types, track each value
            for value in rec.get("values", []):
                records.add((fqdn, rtype, value))
    
    return records


def get_zone_id(zone_name):
    """Get the Cloudflare zone ID for a given zone name."""
    resp = requests.get(
        f"{BASE_URL}/zones",
        headers=HEADERS,
        params={"name": zone_name},
    )
    resp.raise_for_status()
    data = resp.json()
    
    if not data["success"]:
        raise Exception(f"Failed to get zone: {data.get('errors')}")
    
    zones = data["result"]
    if not zones:
        return None
    
    return zones[0]["id"]


def get_dns_records(zone_id):
    """Get all DNS records for a zone."""
    records = []
    page = 1
    per_page = 100
    
    while True:
        resp = requests.get(
            f"{BASE_URL}/zones/{zone_id}/dns_records",
            headers=HEADERS,
            params={"page": page, "per_page": per_page},
        )
        resp.raise_for_status()
        data = resp.json()
        
        if not data["success"]:
            raise Exception(f"Failed to get DNS records: {data.get('errors')}")
        
        records.extend(data["result"])
        
        # Check if there are more pages
        result_info = data.get("result_info", {})
        total_pages = result_info.get("total_pages", 1)
        if page >= total_pages:
            break
        page += 1
    
    return records


def delete_dns_record(zone_id, record_id, name, rtype):
    """Delete a DNS record."""
    print(f"Deleting {name} {rtype}")
    resp = requests.delete(
        f"{BASE_URL}/zones/{zone_id}/dns_records/{record_id}",
        headers=HEADERS,
    )
    resp.raise_for_status()
    data = resp.json()
    
    if not data["success"]:
        raise Exception(f"Failed to delete record: {data.get('errors')}")


def main():
    for filename in os.listdir(DNS_ZONES_DIR):
        if not filename.endswith(".yml"):
            continue
        
        path = os.path.join(DNS_ZONES_DIR, filename)
        with open(path, "r") as f:
            zone_data = yaml.safe_load(f)
        
        zone_name = zone_data["zone_name"]
        
        # Check if this zone uses Cloudflare
        provider = zone_data.get("provider")
        providers = zone_data.get("providers", [])
        
        # Handle both single provider and multiple providers
        is_cloudflare = (
            provider == "cloudflare" or
            "cloudflare" in providers
        )
        
        if not is_cloudflare:
            continue
        
        print(f"\nProcessing zone: {zone_name}")
        
        # Load defined records
        defined = load_defined_records(zone_data, zone_name)
        
        # Get Cloudflare zone ID
        zone_id = get_zone_id(zone_name)
        if zone_id is None:
            print(f"  Zone not found in Cloudflare, skipping")
            continue
        
        # Get existing DNS records
        existing_records = get_dns_records(zone_id)
        
        # Check each existing record
        for record in existing_records:
            rtype = record["type"].upper()
            
            # Skip NS and SOA records (managed by Cloudflare)
            if rtype in ("NS", "SOA"):
                continue
            
            name = record["name"]
            record_id = record["id"]
            
            # Check if this record is defined in our configuration
            should_delete = False
            
            if rtype == "MX":
                # For MX records, check priority and content
                priority = record.get("priority")
                content = record.get("content")
                key = (name, rtype, priority, content)
                if key not in defined:
                    should_delete = True
            else:
                # For other record types, check content
                content = record.get("content")
                key = (name, rtype, content)
                if key not in defined:
                    should_delete = True
            
            if should_delete:
                delete_dns_record(zone_id, record_id, name, rtype)


if __name__ == "__main__":
    main()
