#!/usr/bin/env python3
import os
import yaml
import requests
import sys
import argparse

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


def delete_dns_record(zone_id, record_id, name, rtype, content, dry_run=False):
    """Delete a DNS record."""
    if dry_run:
        print(f"[DRY-RUN] Would delete {name} {rtype} = {content}")
        return
    
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
    # Parse command line arguments
    parser = argparse.ArgumentParser(description="Clean up stray DNS records in Cloudflare")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be deleted without actually deleting")
    parser.add_argument("--debug", action="store_true", help="Enable debug output")
    args = parser.parse_args()
    
    # Also check environment variables for backwards compatibility
    debug = args.debug or os.environ.get("DEBUG", "").lower() in ("1", "true", "yes")
    dry_run = args.dry_run or os.environ.get("DRY_RUN", "").lower() in ("1", "true", "yes")
    
    if dry_run:
        print("=" * 60)
        print("DRY-RUN MODE: No records will be deleted")
        print("=" * 60)
    
    if debug:
        print("Debug mode enabled")
    
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
        
        if debug:
            print(f"\n  Defined records ({len(defined)}):")
            for rec in sorted(defined):
                print(f"    {rec}")
        
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
                
                # TXT records in Cloudflare API are returned with surrounding quotes
                # Strip them for comparison with YAML values
                if rtype == "TXT" and content and content.startswith('"') and content.endswith('"'):
                    content = content[1:-1]
                
                key = (name, rtype, content)
                if key not in defined:
                    should_delete = True
                    if debug:
                        print(f"\n  NOT FOUND in defined records:")
                        print(f"    Cloudflare key: {key}")
                        # Show similar keys for debugging
                        similar = [d for d in defined if d[0] == name and d[1] == rtype]
                        if similar:
                            print(f"    Similar defined records for {name} {rtype}:")
                            for s in similar:
                                print(f"      {s}")
                        else:
                            print(f"    No records found for {name} {rtype}")
            
            if should_delete:
                delete_dns_record(zone_id, record_id, name, rtype, content, dry_run=dry_run)


if __name__ == "__main__":
    main()
