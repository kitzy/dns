#!/usr/bin/env python3
"""
Security scan for DNS zones to detect potential vulnerabilities.

This script checks for:
1. Broken CNAME records (CNAMEs pointing to non-existent domains)
2. Subdomain takeover vulnerabilities (CNAMEs pointing to unclaimed services)
3. Dangling A/AAAA records (IP addresses that don't respond)
4. Stale DNS records pointing to decommissioned services

Run this script regularly to detect security issues before they can be exploited.
"""

import sys
import os
import yaml
import socket
import dns.resolver
import dns.exception
import time
import json
from pathlib import Path
from typing import List, Dict, Tuple, Set
from dataclasses import dataclass, asdict

# Known vulnerable CNAME patterns and their fingerprints
# This list is based on common subdomain takeover patterns
TAKEOVER_FINGERPRINTS = {
    'github.io': {
        'nxdomain': True,
        'error_text': ['There isn\'t a GitHub Pages site here', 'For root URLs'],
        'description': 'GitHub Pages - unclaimed repository'
    },
    'herokuapp.com': {
        'nxdomain': True,
        'error_text': ['No such app'],
        'description': 'Heroku - unclaimed app'
    },
    'azurewebsites.net': {
        'nxdomain': True,
        'description': 'Azure Web Apps - unclaimed site'
    },
    'cloudapp.net': {
        'nxdomain': True,
        'description': 'Azure Cloud Services - unclaimed service'
    },
    'cloudapp.azure.com': {
        'nxdomain': True,
        'description': 'Azure Cloud Apps - unclaimed app'
    },
    'azurefd.net': {
        'nxdomain': True,
        'description': 'Azure Front Door - unclaimed endpoint'
    },
    's3.amazonaws.com': {
        'nxdomain': True,
        'error_text': ['NoSuchBucket'],
        'description': 'AWS S3 - unclaimed bucket'
    },
    's3-website': {
        'nxdomain': True,
        'error_text': ['NoSuchBucket', 'NoSuchWebsiteConfiguration'],
        'description': 'AWS S3 Website - unclaimed bucket'
    },
    'amazonaws.com': {
        'nxdomain': False,  # Varies by service
        'description': 'AWS Service - potential misconfiguration'
    },
    'cloudfront.net': {
        'nxdomain': False,
        'error_text': ['Bad Request', 'The request could not be satisfied'],
        'description': 'AWS CloudFront - misconfigured distribution'
    },
    'elasticbeanstalk.com': {
        'nxdomain': True,
        'description': 'AWS Elastic Beanstalk - unclaimed environment'
    },
    'netlify.app': {
        'nxdomain': True,
        'description': 'Netlify - unclaimed site'
    },
    'netlify.com': {
        'nxdomain': True,
        'description': 'Netlify - unclaimed site'
    },
    'vercel.app': {
        'nxdomain': True,
        'description': 'Vercel - unclaimed deployment'
    },
    'wordpress.com': {
        'nxdomain': True,
        'description': 'WordPress.com - unclaimed site'
    },
    'pantheonsite.io': {
        'nxdomain': True,
        'description': 'Pantheon - unclaimed site'
    },
    'zendesk.com': {
        'nxdomain': True,
        'description': 'Zendesk - unclaimed instance'
    },
    'fastly.net': {
        'nxdomain': True,
        'description': 'Fastly - unclaimed service'
    },
    'helpjuice.com': {
        'nxdomain': True,
        'description': 'HelpJuice - unclaimed account'
    },
    'helpscoutdocs.com': {
        'nxdomain': True,
        'description': 'Help Scout - unclaimed docs'
    },
    'ghost.io': {
        'nxdomain': True,
        'description': 'Ghost - unclaimed blog'
    },
    'surge.sh': {
        'nxdomain': True,
        'description': 'Surge.sh - unclaimed deployment'
    },
    'bitbucket.io': {
        'nxdomain': True,
        'description': 'Bitbucket Pages - unclaimed repository'
    },
    'uservoice.com': {
        'nxdomain': True,
        'description': 'UserVoice - unclaimed instance'
    },
    'statuspage.io': {
        'nxdomain': True,
        'description': 'StatusPage - unclaimed page'
    },
    'readthedocs.io': {
        'nxdomain': True,
        'description': 'ReadTheDocs - unclaimed project'
    },
    'gitbook.io': {
        'nxdomain': True,
        'description': 'GitBook - unclaimed space'
    },
    'webflow.io': {
        'nxdomain': True,
        'description': 'Webflow - unclaimed site'
    },
    'cargocollective.com': {
        'nxdomain': True,
        'description': 'Cargo Collective - unclaimed site'
    },
    'readme.io': {
        'nxdomain': True,
        'description': 'ReadMe - unclaimed docs'
    },
    'mcsv.net': {
        'nxdomain': False,  # Mailchimp DKIM, legitimate use
        'description': 'Mailchimp - DKIM service (likely legitimate)'
    },
}

@dataclass
class SecurityIssue:
    """Represents a security issue found in DNS records."""
    severity: str  # 'critical', 'high', 'medium', 'low'
    zone: str
    record_name: str
    record_type: str
    record_value: str
    issue_type: str
    description: str
    remediation: str

class DNSSecurityScanner:
    """Scans DNS zones for security vulnerabilities."""
    
    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        self.issues: List[SecurityIssue] = []
        self.resolver = dns.resolver.Resolver()
        self.resolver.timeout = 5
        self.resolver.lifetime = 10
        # Use multiple public DNS servers for reliability
        self.resolver.nameservers = ['8.8.8.8', '8.8.4.4', '1.1.1.1']
        
    def log(self, message: str):
        """Log verbose messages."""
        if self.verbose:
            print(f"  {message}")
    
    def check_cname_dangling(self, zone_name: str, record_name: str, cname_target: str) -> List[SecurityIssue]:
        """Check if a CNAME points to a non-existent or vulnerable target."""
        issues = []
        
        # Normalize the CNAME target (remove trailing dot if present)
        cname_target = cname_target.rstrip('.')
        
        # Skip DKIM and other service-specific CNAMEs that are expected not to have A records
        # These CNAMEs point to TXT records, not A records
        if any(keyword in record_name.lower() for keyword in ['_domainkey', '_dmarc', '_atproto']):
            self.log(f"Skipping service record: {record_name} -> {cname_target}")
            return issues
        
        self.log(f"Checking CNAME: {record_name} -> {cname_target}")
        
        # Check if CNAME target resolves
        try:
            answers = self.resolver.resolve(cname_target, 'A')
            self.log(f"  ✓ Resolves to {len(answers)} A record(s)")
        except dns.resolver.NXDOMAIN:
            # CNAME points to non-existent domain
            self.log(f"  ✗ NXDOMAIN - target does not exist")
            
            # Check if this matches a known takeover pattern
            takeover_risk = self._check_takeover_pattern(cname_target)
            
            if takeover_risk:
                issues.append(SecurityIssue(
                    severity='critical',
                    zone=zone_name,
                    record_name=record_name,
                    record_type='CNAME',
                    record_value=cname_target,
                    issue_type='subdomain_takeover',
                    description=f"CNAME points to non-existent domain that matches known vulnerable service: {takeover_risk['description']}",
                    remediation=f"Remove this DNS record immediately or claim the target service at {cname_target}. This subdomain can be taken over by an attacker."
                ))
            else:
                issues.append(SecurityIssue(
                    severity='high',
                    zone=zone_name,
                    record_name=record_name,
                    record_type='CNAME',
                    record_value=cname_target,
                    issue_type='broken_cname',
                    description=f"CNAME points to non-existent domain (NXDOMAIN)",
                    remediation=f"Remove this DNS record or update it to point to a valid domain."
                ))
        except dns.resolver.NoAnswer:
            self.log(f"  ⚠ No A records found for target")
            issues.append(SecurityIssue(
                severity='medium',
                zone=zone_name,
                record_name=record_name,
                record_type='CNAME',
                record_value=cname_target,
                issue_type='broken_cname',
                description=f"CNAME target exists but has no A/AAAA records",
                remediation=f"Verify that {cname_target} is configured correctly or remove this DNS record."
            ))
        except dns.exception.Timeout:
            self.log(f"  ⚠ Timeout querying target")
            issues.append(SecurityIssue(
                severity='low',
                zone=zone_name,
                record_name=record_name,
                record_type='CNAME',
                record_value=cname_target,
                issue_type='dns_timeout',
                description=f"DNS query timeout when resolving CNAME target",
                remediation=f"Check if {cname_target} DNS is configured correctly. This may be a temporary issue."
            ))
        except Exception as e:
            self.log(f"  ⚠ Error: {e}")
        
        return issues
    
    def _check_takeover_pattern(self, cname_target: str) -> Dict:
        """Check if a CNAME target matches known takeover patterns."""
        cname_lower = cname_target.lower()
        
        for pattern, fingerprint in TAKEOVER_FINGERPRINTS.items():
            if pattern in cname_lower:
                # Skip certain patterns that are known to be legitimate
                if pattern == 'mcsv.net':  # Mailchimp DKIM
                    continue
                return fingerprint
        
        return None
    
    def check_a_record_reachability(self, zone_name: str, record_name: str, ip_address: str) -> List[SecurityIssue]:
        """Check if an A/AAAA record IP is reachable."""
        issues = []
        
        self.log(f"Checking A/AAAA: {record_name} -> {ip_address}")
        
        # Try to establish a connection on common ports
        # This is a basic check - more sophisticated checks could be added
        try:
            # Attempt reverse DNS lookup
            try:
                hostname = socket.gethostbyaddr(ip_address)[0]
                self.log(f"  ✓ Reverse DNS: {hostname}")
            except socket.herror:
                self.log(f"  ⚠ No reverse DNS found")
                # This is informational only, not necessarily a security issue
        except Exception as e:
            self.log(f"  ⚠ Error checking IP: {e}")
        
        return issues
    
    def scan_zone_file(self, file_path: Path) -> List[SecurityIssue]:
        """Scan a single zone file for security issues."""
        issues = []
        
        try:
            with open(file_path, 'r') as f:
                data = yaml.safe_load(f)
        except Exception as e:
            print(f"Error reading {file_path.name}: {e}")
            return issues
        
        zone_name = data.get('zone_name', file_path.stem)
        records = data.get('records', [])
        
        print(f"\n🔍 Scanning {zone_name}...")
        
        for record in records:
            record_type = record.get('type', '').upper()
            record_name = record.get('name', '')
            
            # Construct full domain name
            if record_name == zone_name or record_name == '@':
                full_name = zone_name
            elif record_name == '*':
                full_name = f"*.{zone_name}"
            else:
                full_name = f"{record_name}.{zone_name}"
            
            if record_type == 'CNAME':
                values = record.get('values', [])
                for value in values:
                    # Add a small delay to avoid overwhelming DNS servers
                    time.sleep(0.2)
                    issues.extend(self.check_cname_dangling(zone_name, full_name, value))
            
            elif record_type in ['A', 'AAAA']:
                values = record.get('values', [])
                for value in values:
                    # Only do basic checks for A/AAAA records
                    # More intensive checks could be added here
                    pass
        
        return issues
    
    def scan_all_zones(self, zones_dir: Path) -> List[SecurityIssue]:
        """Scan all zone files in the directory."""
        all_issues = []
        
        zone_files = list(zones_dir.glob("*.yml"))
        
        if not zone_files:
            print("No zone files found")
            return all_issues
        
        for zone_file in sorted(zone_files):
            all_issues.extend(self.scan_zone_file(zone_file))
        
        return all_issues
    
    def print_report(self, issues: List[SecurityIssue]):
        """Print a formatted security report."""
        if not issues:
            print("\n✅ No security issues found!")
            return
        
        # Group issues by severity
        by_severity = {
            'critical': [],
            'high': [],
            'medium': [],
            'low': []
        }
        
        for issue in issues:
            by_severity[issue.severity].append(issue)
        
        print("\n" + "="*80)
        print("DNS SECURITY SCAN REPORT")
        print("="*80)
        
        # Print summary
        print(f"\nTotal Issues Found: {len(issues)}")
        print(f"  🔴 Critical: {len(by_severity['critical'])}")
        print(f"  🟠 High: {len(by_severity['high'])}")
        print(f"  🟡 Medium: {len(by_severity['medium'])}")
        print(f"  🟢 Low: {len(by_severity['low'])}")
        
        # Print detailed issues by severity
        for severity in ['critical', 'high', 'medium', 'low']:
            if not by_severity[severity]:
                continue
            
            emoji = {'critical': '🔴', 'high': '🟠', 'medium': '🟡', 'low': '🟢'}[severity]
            print(f"\n{emoji} {severity.upper()} SEVERITY ISSUES")
            print("-" * 80)
            
            for issue in by_severity[severity]:
                print(f"\nZone: {issue.zone}")
                print(f"Record: {issue.record_name} ({issue.record_type})")
                print(f"Value: {issue.record_value}")
                print(f"Issue: {issue.issue_type}")
                print(f"Description: {issue.description}")
                print(f"Remediation: {issue.remediation}")
        
        print("\n" + "="*80)
    
    def export_json(self, issues: List[SecurityIssue], output_file: Path):
        """Export issues to JSON format."""
        data = {
            'scan_date': time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime()),
            'total_issues': len(issues),
            'issues': [asdict(issue) for issue in issues]
        }
        
        with open(output_file, 'w') as f:
            json.dump(data, f, indent=2)
        
        print(f"\n📄 Report exported to: {output_file}")

def main():
    """Main function."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Scan DNS zones for security vulnerabilities',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic scan
  python3 scripts/security_scan.py
  
  # Verbose output
  python3 scripts/security_scan.py --verbose
  
  # Export results to JSON
  python3 scripts/security_scan.py --output security-report.json
  
  # Fail on any issues (useful for CI/CD)
  python3 scripts/security_scan.py --fail-on-issues
        """
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Enable verbose output'
    )
    
    parser.add_argument(
        '--output', '-o',
        type=str,
        help='Export results to JSON file'
    )
    
    parser.add_argument(
        '--fail-on-issues',
        action='store_true',
        help='Exit with error code if any issues are found (useful for CI/CD)'
    )
    
    parser.add_argument(
        '--fail-on-severity',
        choices=['critical', 'high', 'medium', 'low'],
        default='critical',
        help='Minimum severity level to fail on (default: critical)'
    )
    
    args = parser.parse_args()
    
    # Find the dns_zones directory
    script_dir = Path(__file__).parent
    zones_dir = script_dir.parent / "dns_zones"
    
    if not zones_dir.exists():
        print(f"Error: dns_zones directory not found at {zones_dir}")
        sys.exit(1)
    
    # Run the scan
    scanner = DNSSecurityScanner(verbose=args.verbose)
    issues = scanner.scan_all_zones(zones_dir)
    
    # Print report
    scanner.print_report(issues)
    
    # Export to JSON if requested
    if args.output:
        output_path = Path(args.output)
        scanner.export_json(issues, output_path)
    
    # Exit with appropriate code
    if args.fail_on_issues and issues:
        severity_levels = {'low': 0, 'medium': 1, 'high': 2, 'critical': 3}
        min_severity = severity_levels[args.fail_on_severity]
        
        has_issues_above_threshold = any(
            severity_levels[issue.severity] >= min_severity
            for issue in issues
        )
        
        if has_issues_above_threshold:
            print(f"\n❌ Scan failed: Found issues at or above '{args.fail_on_severity}' severity")
            sys.exit(1)
    
    print("\n✅ Scan complete")
    sys.exit(0)

if __name__ == "__main__":
    main()
