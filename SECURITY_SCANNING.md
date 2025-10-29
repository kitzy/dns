# DNS Security Scanning

This repository includes automated security scanning to detect DNS vulnerabilities, including:

- **Broken CNAME records** - CNAMEs pointing to non-existent domains
- **Subdomain takeover vulnerabilities** - CNAMEs pointing to unclaimed cloud services
- **Dangling DNS records** - Records pointing to decommissioned resources

## Features

### Automated Weekly Scans

The security scan runs automatically every Monday at 9:00 AM UTC via GitHub Actions. If critical or high-severity issues are detected, the workflow will:

1. Create or update a GitHub issue with details
2. Upload a detailed JSON report as an artifact
3. Fail the workflow to notify repository administrators

### Manual Scans

You can manually trigger a security scan in two ways:

#### Via GitHub Actions
1. Go to the Actions tab
2. Select "Weekly DNS Security Scan"
3. Click "Run workflow"

#### Via Command Line
```bash
# Basic scan
python3 scripts/security_scan.py

# Verbose output
python3 scripts/security_scan.py --verbose

# Export results to JSON
python3 scripts/security_scan.py --output security-report.json

# Fail on any issues (useful for CI/CD)
python3 scripts/security_scan.py --fail-on-issues

# Fail on medium severity or higher
python3 scripts/security_scan.py --fail-on-issues --fail-on-severity medium
```

### Pull Request Checks

The security scan also runs on pull requests that modify DNS zone files, providing immediate feedback on potential security issues introduced by changes.

## Dependencies

The security scan requires the following Python packages:

```bash
pip install pyyaml dnspython
```

## Vulnerability Detection

### Subdomain Takeover

The scanner checks for CNAME records pointing to popular cloud services that may be vulnerable to subdomain takeover, including:

- GitHub Pages (`*.github.io`)
- Heroku (`*.herokuapp.com`)
- Azure Web Apps (`*.azurewebsites.net`)
- AWS S3 (`*.s3.amazonaws.com`, S3 website endpoints)
- AWS CloudFront (`*.cloudfront.net`)
- Netlify (`*.netlify.app`)
- Vercel (`*.vercel.app`)
- And many more...

When a CNAME points to one of these services and the target doesn't exist (NXDOMAIN), it's flagged as a critical vulnerability.

### Broken CNAME Detection

The scanner resolves all CNAME records to ensure they point to valid, active domains. Issues are categorized by severity:

- **Critical**: CNAME pointing to a known vulnerable service
- **High**: CNAME pointing to a non-existent domain (NXDOMAIN)
- **Medium**: CNAME target exists but has no A/AAAA records
- **Low**: DNS timeout or temporary resolution issues

## Security Report Format

The JSON security report includes:

```json
{
  "scan_date": "2025-10-28 09:00:00 UTC",
  "total_issues": 2,
  "issues": [
    {
      "severity": "critical",
      "zone": "example.com",
      "record_name": "old.example.com",
      "record_type": "CNAME",
      "record_value": "myapp.herokuapp.com",
      "issue_type": "subdomain_takeover",
      "description": "CNAME points to non-existent domain that matches known vulnerable service: Heroku - unclaimed app",
      "remediation": "Remove this DNS record immediately or claim the target service at myapp.herokuapp.com. This subdomain can be taken over by an attacker."
    }
  ]
}
```

## Severity Levels

- **🔴 Critical**: Immediate action required - subdomain takeover vulnerabilities
- **🟠 High**: Broken CNAMEs that should be fixed soon
- **🟡 Medium**: Configuration issues that may affect functionality
- **🟢 Low**: Informational or temporary issues

## Remediation

When security issues are detected:

1. **Critical/High**: Remove the broken DNS record immediately, or reclaim the service
2. **Medium**: Verify the configuration and fix or remove the record
3. **Low**: Monitor the issue; may resolve on its own

## Configuration

### Adjusting Scan Schedule

Edit `.github/workflows/security-scan.yml` to change the scan schedule:

```yaml
on:
  schedule:
    # Change the cron expression (default: Mondays at 9 AM UTC)
    - cron: '0 9 * * 1'
```

### Modifying Failure Criteria

By default, the workflow fails only on critical issues. To change this:

```yaml
- name: Fail if critical issues found
  if: steps.check_issues.outputs.critical != '0'
  run: |
    echo "::error::Found critical security issues"
    exit 1
```

Change `critical` to `high`, `medium`, or `low` as needed.

## Best Practices

1. **Review alerts promptly** - Critical vulnerabilities should be addressed within hours
2. **Remove unused records** - Clean up DNS records for decommissioned services
3. **Use meaningful subdomain names** - Avoid generic names that might be claimed by others
4. **Monitor scan reports** - Review the weekly scan results even if no issues are found
5. **Test changes locally** - Run the security scan before committing DNS changes

## Limitations

- The scanner checks DNS resolution but not HTTP endpoints
- Some legitimate configurations may be flagged (e.g., intentionally parked domains)
- DNS propagation delays may cause temporary false positives
- The scanner uses public DNS resolvers and may not reflect internal DNS configurations

## Contributing

To add new vulnerability fingerprints, edit `TAKEOVER_FINGERPRINTS` in `scripts/security_scan.py`.

## References

- [OWASP Subdomain Takeover](https://owasp.org/www-community/attacks/Subdomain_Takeover)
- [Can I Take Over XYZ?](https://github.com/EdOverflow/can-i-take-over-xyz) - Comprehensive subdomain takeover reference
