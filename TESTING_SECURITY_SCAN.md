# Testing the DNS Security Scanner

## Quick Test

To test the security scanner on your zones:

```bash
# Install dependencies
pip install -r requirements.txt

# Run a basic scan
python3 scripts/security_scan.py

# Run with verbose output
python3 scripts/security_scan.py --verbose

# Export results to JSON
python3 scripts/security_scan.py --output security-report.json
```

## Testing Subdomain Takeover Detection

The scanner detects when CNAMEs point to vulnerable cloud services. Here's what it looks for:

### Example Vulnerable CNAME

If you had a CNAME like this in your zone file:

```yaml
records:
  - name: "old-app"
    type: CNAME
    ttl: 300
    values:
      - "myapp.herokuapp.com"
```

And `myapp.herokuapp.com` doesn't exist (returns NXDOMAIN), the scanner would flag it as:

```
🔴 CRITICAL SEVERITY ISSUES
--------------------------------------------------------------------------------

Zone: example.com
Record: old-app.example.com (CNAME)
Value: myapp.herokuapp.com
Issue: subdomain_takeover
Description: CNAME points to non-existent domain that matches known vulnerable 
             service: Heroku - unclaimed app
Remediation: Remove this DNS record immediately or claim the target service at 
             myapp.herokuapp.com. This subdomain can be taken over by an attacker.
```

## Test Cases

### 1. Broken CNAME (Non-Existent Domain)

**Zone file:**
```yaml
records:
  - name: "test"
    type: CNAME
    ttl: 300
    values:
      - "nonexistent-domain-12345.com"
```

**Expected Result:** HIGH severity - broken_cname

### 2. Subdomain Takeover Risk

**Zone file:**
```yaml
records:
  - name: "blog"
    type: CNAME
    ttl: 300
    values:
      - "myblog.ghost.io"  # If this doesn't exist
```

**Expected Result:** CRITICAL severity - subdomain_takeover (if ghost.io site doesn't exist)

### 3. Valid CNAME

**Zone file:**
```yaml
records:
  - name: "www"
    type: CNAME
    ttl: 300
    values:
      - "example.github.io"  # If this exists and resolves
```

**Expected Result:** No issues

### 4. DKIM/Service Records (Should be Skipped)

**Zone file:**
```yaml
records:
  - name: "google._domainkey"
    type: CNAME
    ttl: 300
    values:
      - "dkim.example.com"
```

**Expected Result:** No issues (automatically skipped)

## Manual Testing with dig

You can manually verify what the scanner will find:

```bash
# Check if a CNAME target exists
dig +short myapp.herokuapp.com A

# If it returns nothing, it's either NXDOMAIN or has no A records
dig myapp.herokuapp.com

# Check CNAME resolution
dig +short www.example.com CNAME
```

## Current Scan Results

Based on your current DNS zones, the scanner found:

- ✅ Most CNAMEs are valid and resolve correctly
- ⚠️ One broken CNAME in `kitzysound.com` pointing to a Google verification domain
- ✅ DKIM CNAMEs are correctly skipped (they point to TXT records, not A records)

## Severity Levels Explained

| Severity | When Triggered | Action Required |
|----------|---------------|-----------------|
| 🔴 Critical | CNAME to unclaimed cloud service | **Immediate** - Delete record or claim service |
| 🟠 High | CNAME to non-existent domain | **Soon** - Delete or fix the record |
| 🟡 Medium | CNAME target has no A records | **Review** - May be intentional |
| 🟢 Low | DNS timeout or temporary issue | **Monitor** - May resolve itself |

## Integration Testing

The GitHub Actions workflow can be tested by:

1. Creating a test branch
2. Adding a vulnerable CNAME to a zone file
3. Opening a pull request
4. Checking the workflow run for security scan results

## Troubleshooting

### "ModuleNotFoundError: No module named 'dns'"

```bash
pip install dnspython
```

### "No zone files found"

Make sure you're running from the repository root:
```bash
cd /path/to/dns
python3 scripts/security_scan.py
```

### False Positives

Some legitimate configurations may be flagged:

- **DKIM CNAMEs**: Automatically skipped
- **Intentionally parked domains**: Use `--fail-on-severity critical` to ignore
- **Staging environments**: Consider separate zone files

## Advanced Usage

### Fail on specific severity levels

```bash
# Fail only on critical issues (default)
python3 scripts/security_scan.py --fail-on-issues

# Fail on high severity or above
python3 scripts/security_scan.py --fail-on-issues --fail-on-severity high

# Fail on any issues
python3 scripts/security_scan.py --fail-on-issues --fail-on-severity low
```

### Automate with cron

Add to your crontab for weekly scans:

```bash
0 9 * * 1 cd /path/to/dns && python3 scripts/security_scan.py --output /var/log/dns-scan.json
```
