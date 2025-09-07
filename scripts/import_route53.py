#!/usr/bin/env python3
import os
import subprocess
import yaml
import boto3

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DNS_ZONES_DIR = os.path.join(REPO_ROOT, "dns_zones")

route53 = boto3.client('route53')

def in_state(address: str) -> bool:
    result = subprocess.run([
        "terraform", "state", "show", address
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return result.returncode == 0

for filename in os.listdir(DNS_ZONES_DIR):
    if not filename.endswith('.yml'):
        continue
    path = os.path.join(DNS_ZONES_DIR, filename)
    with open(path, 'r') as f:
        zone_data = yaml.safe_load(f)

    zone_name = zone_data['zone_name']
    # Lookup zone ID
    resp = route53.list_hosted_zones_by_name(DNSName=zone_name)
    hosted_zone = next((z for z in resp['HostedZones'] if z['Name'].rstrip('.') == zone_name), None)
    if hosted_zone is None:
        # Zone does not exist yet; Terraform will create it
        continue
    zone_id = hosted_zone['Id'].split('/')[-1]

    zone_address = f'aws_route53_zone.this["{zone_name}"]'
    if not in_state(zone_address):
        subprocess.run(["terraform", "import", zone_address, zone_id], check=False)

    for rec in zone_data.get('records', []):
        rtype = rec['type'].upper()
        if rtype in ('NS', 'SOA'):
            continue
        name = rec['name']
        fqdn = name if name == zone_name or name.endswith('.' + zone_name) else f"{name}.{zone_name}"
        set_id = rec.get('set_identifier')
        import_id = f"{zone_id}_{fqdn}_{rtype}"
        key = f"{zone_name}_{name}_{rtype}"
        if set_id:
            import_id += f"_{set_id}"
            key += f"_{set_id}"
        record_address = f'aws_route53_record.this["{key}"]'
        if not in_state(record_address):
            subprocess.run(["terraform", "import", record_address, import_id], check=False)
