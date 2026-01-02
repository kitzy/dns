#!/usr/bin/env python3
"""
Cleanup Cloudflare DNS records not managed by Terraform.

Skips records managed by External DNS (identified by _external-dns- TXT records).
"""

import subprocess
import json
import sys
from typing import Set, Dict, List

def get_terraform_managed_records() -> Set[str]:
    """Get set of record names managed by Terraform."""
    try:
        result = subprocess.run(
            ["terraform", "show", "-json"],
            capture_output=True,
            text=True,
            check=True
        )
        
        state = json.loads(result.stdout)
        managed_records = set()
        
        if "values" in state and "root_module" in state["values"]:
            resources = state["values"]["root_module"].get("resources", [])
            
            for resource in resources:
                if resource["type"] == "cloudflare_record":
                    name = resource["values"]["name"]
                    zone = resource["values"]["zone_id"]
                    managed_records.add(f"{zone}:{name}")
        
        return managed_records
    
    except subprocess.CalledProcessError as e:
        print(f"Error running terraform show: {e}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error parsing terraform state: {e}", file=sys.stderr)
        sys.exit(1)

def get_external_dns_managed_records(zone_id: str, api_token: str) -> Set[str]:
    """Get set of record names managed by External DNS."""
    try:
        import requests
        
        headers = {
            "Authorization": f"Bearer {api_token}",
            "Content-Type": "application/json"
        }
        
        response = requests.get(
            f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records",
            headers=headers,
            params={"type": "TXT", "per_page": 1000}
        )
        response.raise_for_status()
        
        external_dns_records = set()
        for record in response.json()["result"]:
            # External DNS creates TXT records like "_external-dns-hello.kitzy.net"
            if record["name"].startswith("_external-dns-"):
                # Extract the actual record name
                # "_external-dns-hello.kitzy.net" -> "hello.kitzy.net"
                actual_name = record["name"].replace("_external-dns-", "", 1)
                external_dns_records.add(actual_name)
        
        return external_dns_records
    
    except Exception as e:
        print(f"Warning: Could not fetch External DNS records: {e}", file=sys.stderr)
        return set()

def get_cloudflare_records(zone_id: str, api_token: str) -> List[Dict]:
    """Get all DNS records from Cloudflare."""
    try:
        import requests
        
        headers = {
            "Authorization": f"Bearer {api_token}",
            "Content-Type": "application/json"
        }
        
        response = requests.get(
            f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records",
            headers=headers,
            params={"per_page": 1000}
        )
        response.raise_for_status()
        
        return response.json()["result"]
    
    except Exception as e:
        print(f"Error fetching Cloudflare records: {e}", file=sys.stderr)
        sys.exit(1)

def should_skip_record(record: Dict, external_dns_managed: Set[str]) -> bool:
    """Determine if a record should be skipped from cleanup."""
    name = record["name"]
    record_type = record["type"]
    
    # Skip External DNS ownership TXT records
    if record_type == "TXT" and name.startswith("_external-dns-"):
        return True
    
    # Skip records managed by External DNS
    if name in external_dns_managed:
        return True
    
    # Skip root domain records (usually important)
    if name == record["zone_name"]:
        return True
    
    # Skip common infrastructure records
    skip_patterns = [
        "_acme-challenge",  # Let's Encrypt challenges
        "_dmarc",           # Email authentication
        "_domainkey",       # DKIM records
    ]
    
    for pattern in skip_patterns:
        if pattern in name:
            return True
    
    return False

def main():
    # Get configuration from environment or Terraform
    zone_id = subprocess.run(
        ["terraform", "output", "-raw", "zone_id"],
        capture_output=True,
        text=True,
        check=True
    ).stdout.strip()
    
    api_token = subprocess.run(
        ["op", "read", "op://GitHub/CloudflareAPI/API_TOKEN"],
        capture_output=True,
        text=True,
        check=True
    ).stdout.strip()
    
    print(f"Checking DNS records for zone {zone_id}...")
    
    # Get managed records
    terraform_managed = get_terraform_managed_records()
    external_dns_managed = get_external_dns_managed_records(zone_id, api_token)
    cloudflare_records = get_cloudflare_records(zone_id, api_token)
    
    print(f"Terraform manages {len(terraform_managed)} records")
    print(f"External DNS manages {len(external_dns_managed)} records")
    print(f"Cloudflare has {len(cloudflare_records)} total records")
    
    # Find records to delete
    records_to_delete = []
    
    for record in cloudflare_records:
        record_key = f"{zone_id}:{record['name']}"
        
        # Skip if managed by Terraform
        if record_key in terraform_managed:
            continue
        
        # Skip if managed by External DNS or matches skip patterns
        if should_skip_record(record, external_dns_managed):
            print(f"Skipping {record['type']} record: {record['name']} (External DNS or protected)")
            continue
        
        records_to_delete.append(record)
    
    if not records_to_delete:
        print("\nNo unmanaged records found. All clean!")
        return
    
    # Show records to delete
    print(f"\nFound {len(records_to_delete)} unmanaged records:")
    for record in records_to_delete:
        print(f"  - {record['type']} {record['name']} -> {record['content']}")
    
    # Confirm deletion
    response = input("\nDelete these records? [y/N]: ")
    if response.lower() != 'y':
        print("Aborted.")
        return
    
    # Delete records
    import requests
    headers = {
        "Authorization": f"Bearer {api_token}",
        "Content-Type": "application/json"
    }
    
    for record in records_to_delete:
        try:
            response = requests.delete(
                f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records/{record['id']}",
                headers=headers
            )
            response.raise_for_status()
            print(f"Deleted {record['type']} record: {record['name']}")
        except Exception as e:
            print(f"Error deleting {record['name']}: {e}", file=sys.stderr)
    
    print("\nCleanup complete!")

if __name__ == "__main__":
    main()