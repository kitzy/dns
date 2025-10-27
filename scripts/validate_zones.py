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
    
    # Check provider field(s) - support both single and multi-provider formats
    has_provider = 'provider' in data
    has_providers = 'providers' in data
    
    if not has_provider and not has_providers:
        errors.append("Missing required field: either 'provider' or 'providers'")
    elif has_provider and has_providers:
        errors.append("Cannot specify both 'provider' and 'providers' fields. Use one or the other.")
    elif has_provider:
        # Single provider format
        provider = data['provider']
        if not isinstance(provider, str):
            errors.append(f"Provider must be a string, got {type(provider).__name__}")
        elif provider not in SUPPORTED_PROVIDERS:
            errors.append(f"Unsupported provider '{provider}'. Supported providers: {', '.join(sorted(SUPPORTED_PROVIDERS))}")
    elif has_providers:
        # Multi-provider format
        providers = data['providers']
        if not isinstance(providers, list):
            errors.append(f"Providers must be a list, got {type(providers).__name__}")
        elif len(providers) == 0:
            errors.append("Providers list cannot be empty")
        else:
            for i, provider in enumerate(providers):
                if not isinstance(provider, str):
                    errors.append(f"Provider at index {i} must be a string, got {type(provider).__name__}")
                elif provider not in SUPPORTED_PROVIDERS:
                    errors.append(f"Unsupported provider '{provider}' at index {i}. Supported providers: {', '.join(sorted(SUPPORTED_PROVIDERS))}")
            
            # Check for duplicates
            if len(providers) != len(set(providers)):
                errors.append("Duplicate providers found in providers list")
    
    # Check records field
    if 'records' not in data:
        errors.append("Missing required field: records")
    elif not isinstance(data['records'], list):
        errors.append("Records field must be a list")
    else:
        # Validate individual records
        for i, record in enumerate(data['records']):
            if not isinstance(record, dict):
                errors.append(f"Record at index {i} must be an object")
                continue
                
            # Check optional proxied field (Cloudflare only)
            if 'proxied' in record:
                if not isinstance(record['proxied'], bool):
                    errors.append(f"Record at index {i}: 'proxied' field must be a boolean (true/false)")
                
            # Check if it's an MX record with the new format
            if record.get('type', '').upper() == 'MX' and 'mx_records' in record:
                if not isinstance(record['mx_records'], list):
                    errors.append(f"MX record at index {i}: mx_records must be a list")
                else:
                    for j, mx in enumerate(record['mx_records']):
                        if not isinstance(mx, dict):
                            errors.append(f"MX record at index {i}, mx_records[{j}] must be an object")
                            continue
                        if 'priority' not in mx:
                            errors.append(f"MX record at index {i}, mx_records[{j}] missing 'priority' field")
                        elif not isinstance(mx['priority'], int):
                            errors.append(f"MX record at index {i}, mx_records[{j}] priority must be an integer")
                        if 'value' not in mx:
                            errors.append(f"MX record at index {i}, mx_records[{j}] missing 'value' field")
                        elif not isinstance(mx['value'], str):
                            errors.append(f"MX record at index {i}, mx_records[{j}] value must be a string")
    
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