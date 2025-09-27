#!/usr/bin/env python3
"""
Validate DNS zone configuration files.

This script checks that:
1. Each zone file has a valid 'provider' field
2. The provider is one of the supported values: 'route53' or 'cloudflare'
3. The zone_name field is present and matches the filename
"""

import sys
import os
import yaml
from pathlib import Path

# Supported DNS providers
SUPPORTED_PROVIDERS = frozenset(['route53', 'cloudflare'])

def validate_zone_file(file_path):
    """Validate a single zone file."""
    errors = []
    
    try:
        with open(file_path, 'r') as f:
            data = yaml.safe_load(f)
    except yaml.YAMLError as e:
        errors.append(f"YAML parsing error: {e}")
        return errors
    except Exception as e:
        errors.append(f"Error reading file: {e}")
        return errors
    
    if not isinstance(data, dict):
        errors.append("Zone file must contain a YAML object")
        return errors
    
    # Check zone_name field
    if 'zone_name' not in data:
        errors.append("Missing required field: zone_name")
    else:
        zone_name = data['zone_name']
        expected_filename = f"{zone_name}.yml"
        actual_filename = file_path.name
        if actual_filename != expected_filename:
            errors.append(f"Filename '{actual_filename}' does not match zone_name '{zone_name}' (expected '{expected_filename}')")
    
    # Check provider field
    if 'provider' not in data:
        errors.append("Missing required field: provider")
    else:
        provider = data['provider']
        if not isinstance(provider, str):
            errors.append(f"Provider must be a string, got {type(provider).__name__}")
        elif provider not in SUPPORTED_PROVIDERS:
            errors.append(f"Unsupported provider '{provider}'. Supported providers: {', '.join(sorted(SUPPORTED_PROVIDERS))}")
    
    # Check records field
    if 'records' not in data:
        errors.append("Missing required field: records")
    elif not isinstance(data['records'], list):
        errors.append("Records field must be a list")
    
    return errors

def main():
    """Main validation function."""
    # Find the dns_zones directory
    script_dir = Path(__file__).parent
    zones_dir = script_dir.parent / "dns_zones"
    
    if not zones_dir.exists():
        print(f"Error: dns_zones directory not found at {zones_dir}")
        sys.exit(1)
    
    # Find all .yml files in the zones directory
    zone_files = list(zones_dir.glob("*.yml"))
    
    if not zone_files:
        print("Warning: No zone files found in dns_zones directory")
        sys.exit(0)
    
    total_errors = 0
    
    for zone_file in sorted(zone_files):
        errors = validate_zone_file(zone_file)
        
        if errors:
            print(f"\n❌ {zone_file.name}:")
            for error in errors:
                print(f"  - {error}")
            total_errors += len(errors)
        else:
            print(f"✅ {zone_file.name}")
    
    if total_errors > 0:
        print(f"\n❌ Validation failed with {total_errors} error(s)")
        sys.exit(1)
    else:
        print(f"\n✅ All {len(zone_files)} zone files are valid")
        sys.exit(0)

if __name__ == "__main__":
    main()