# Changelog

All notable changes to this DNS management repository will be documented in this file.

## [Unreleased]

### Added - 2025-10-28

#### 🔒 DNS Security Scanning System

A comprehensive security scanning system for detecting DNS vulnerabilities:

**New Files:**
- `scripts/security_scan.py` - Python script for scanning DNS zones
- `.github/workflows/security-scan.yml` - Weekly automated scanning workflow
- `SECURITY_SCANNING.md` - Complete security scanning documentation
- `TESTING_SECURITY_SCAN.md` - Testing and troubleshooting guide
- `IMPLEMENTATION_SUMMARY.md` - Implementation details and results
- `QUICK_REFERENCE.md` - Quick command reference
- `requirements.txt` - Python dependencies

**Features:**
- ✅ Detects broken CNAME records (pointing to non-existent domains)
- ✅ Identifies subdomain takeover vulnerabilities
- ✅ Checks against 30+ known vulnerable cloud service patterns
- ✅ Weekly automated scans via GitHub Actions (Mondays at 9 AM UTC)
- ✅ Pull request integration - scans on DNS zone changes
- ✅ Automatic GitHub issue creation for critical/high severity findings
- ✅ JSON report generation with 90-day artifact retention
- ✅ Smart filtering (automatically skips DKIM and service records)
- ✅ Configurable severity thresholds and failure criteria

**Vulnerability Detection:**
- GitHub Pages, Heroku, Azure, AWS S3/CloudFront, Netlify, Vercel
- WordPress.com, Ghost, Fastly, Zendesk, StatusPage
- And 20+ more cloud services vulnerable to subdomain takeover

**Updated Files:**
- `README.md` - Added security scanning section and updated installation instructions
- `.gitignore` - Added `security-report.json` to ignored files

**Dependencies:**
- `dnspython>=2.4.0` - DNS resolution and query functionality
- `pyyaml>=6.0` - YAML parsing (already used)
- `yamllint>=1.30.0` - YAML linting (already used)

**Usage:**
```bash
# Install dependencies
pip install -r requirements.txt

# Run security scan
python3 scripts/security_scan.py --verbose

# Export results
python3 scripts/security_scan.py --output security-report.json
```

**Security Impact:**
- Proactive detection of DNS vulnerabilities before exploitation
- Reduced risk of subdomain takeover attacks
- Automated monitoring with zero ongoing cost
- Historical audit trail via GitHub Actions artifacts

---

## Previous Changes

_(No previous changelog entries - this is the first structured changelog)_

## Legend

- 🔒 Security-related changes
- ✨ New features
- 🐛 Bug fixes
- 📝 Documentation
- 🔧 Configuration changes
- ⚡ Performance improvements
- 🎨 Code style/formatting
- ♻️ Refactoring
