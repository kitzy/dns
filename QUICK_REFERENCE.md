# DNS Security Scanner - Quick Reference

## Installation

```bash
pip install -r requirements.txt
```

## Basic Commands

```bash
# Run security scan
python3 scripts/security_scan.py

# Verbose output
python3 scripts/security_scan.py --verbose

# Export to JSON
python3 scripts/security_scan.py --output report.json

# Fail on any issues (CI/CD)
python3 scripts/security_scan.py --fail-on-issues
```

## Severity Levels

| Icon | Severity | Meaning | Action |
|------|----------|---------|--------|
| 🔴 | Critical | Subdomain takeover risk | **Fix immediately** |
| 🟠 | High | Broken CNAME | Fix soon |
| 🟡 | Medium | No A/AAAA records | Review |
| 🟢 | Low | Temporary issue | Monitor |

## GitHub Actions

- **Schedule:** Every Monday at 9:00 AM UTC
- **Manual:** Actions → "Weekly DNS Security Scan" → "Run workflow"
- **On PR:** Automatic scan when DNS zones change

## Common Issues

### Broken CNAME Found
```yaml
# Remove or fix the record in dns_zones/*.yml
records:
  - name: "old-subdomain"
    type: CNAME
    values:
      - "nonexistent.com"  # ← Remove this
```

### Subdomain Takeover Risk
```yaml
# URGENT: Remove immediately or claim the service
records:
  - name: "blog"
    type: CNAME
    values:
      - "myapp.herokuapp.com"  # ← If this doesn't exist, delete it!
```

## Viewing Reports

### GitHub Actions
1. Go to Actions tab
2. Click on "Weekly DNS Security Scan"
3. Click on latest run
4. Download `security-report` artifact

### Local JSON Report
```bash
python3 scripts/security_scan.py --output report.json
cat report.json | jq .
```

## Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| `ModuleNotFoundError: No module named 'dns'` | `pip install dnspython` |
| `No zone files found` | Run from repo root: `cd /path/to/dns` |
| False positive for DKIM | Already filtered - skip `_domainkey` |

## Files Created

- `scripts/security_scan.py` - Scanner script
- `.github/workflows/security-scan.yml` - Weekly automation
- `SECURITY_SCANNING.md` - Full documentation
- `TESTING_SECURITY_SCAN.md` - Testing guide
- `requirements.txt` - Dependencies

## Support

For detailed information:
- 📖 [Full Documentation](SECURITY_SCANNING.md)
- 🧪 [Testing Guide](TESTING_SECURITY_SCAN.md)
- 📊 [Implementation Summary](IMPLEMENTATION_SUMMARY.md)
