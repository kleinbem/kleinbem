# Fleet Maintenance Automation

Automated auditing and monitoring for the kleinbem infrastructure fleet, derived from [CI-HARDENING-RECOMMENDATIONS.md](../CI-HARDENING-RECOMMENDATIONS.md).

## Overview

Three complementary systems monitor code quality and dependency health:

### 1. Version Pinning Audit (`just audit-versions`)
**Purpose:** Detect pinned package versions approaching deprecation in nixpkgs.

**Triggers:**
- Manual: `just audit-versions [filter]`
- Weekly: GitHub Actions (Tuesday 09:00 UTC)

**Output:** Lists all `platformToolsVersion`, `androidVersion`, etc., flags any approaching deprecation.

**Example:**
```bash
just audit-versions nix  # Audit nix-* repos only
```

---

### 2. Flake Lock Freshness Check (`just check-flake-lock-age`)
**Purpose:** Alert when flake.lock files haven't been updated in >30 days.

**Triggers:**
- Manual: `just check-flake-lock-age`
- Weekly: GitHub Actions (Wednesday 09:00 UTC)

**Remediation:** `just in <repo> flake update` to refresh

**Example:**
```bash
just check-flake-lock-age
# ⚠️  github-config: 60 days old (2026-06-18)
# ✅ nix-config: 1 days old (2026-08-16)
```

---

### 3. Transitive Dependency Monitoring (`audit-transitive-deps.sh`)
**Purpose:** Detect major version bumps in C libraries (FFmpeg, OpenSSL, curl, etc.) that break dependent packages.

**Triggers:**
- Manual: `just audit-transitive-deps [filter]`
- On flake.lock PR changes (CI comments immediately)
- Weekly: GitHub Actions (Thursday 10:00 UTC)

**Watches:** FFmpeg, OpenSSL, curl, zlib, libpng, libjpeg, lua, Python3, PostgreSQL, libxml2

**Example:**
```bash
just audit-transitive-deps nix-config
# 🔗 Auditing transitive dependencies for: nix-config
#    nixpkgs rev: f6e5b...
# ⚠️  ffmpeg: major version bump (8 → 9)
#    old: 8.1.1, new: 9.0.0
```

---

## GitHub Actions Workflows

All three audits run as GitHub Actions in `.github/workflows/`:

| Workflow | Trigger | Schedule | Action |
|----------|---------|----------|--------|
| `audit-versions.yaml` | Manual / Schedule | Tue 09:00 UTC | Reports version findings |
| `check-flake-lock-age.yaml` | Manual / Schedule | Wed 09:00 UTC | Alerts on stale locks |
| `audit-transitive-deps.yaml` | PR (flake.lock) / Schedule | Thu 10:00 UTC | Comments on breaking changes |

**All workflows archive results for 90 days** in GitHub Actions artifacts.

---

## Pre-commit Hook: Version Consistency

Prevents version drift before commits:

```bash
git add platformToolsVersion-change1.nix platformToolsVersion-change2.nix
git commit -m "..."

# ⚠️  Version consistency check: Found multiple versions of same key
# platformToolsVersion=36.0.1
# platformToolsVersion=37.0.1
# (commit fails)
```

Configured in `nix-devshells/shells/default/default.nix`.

---

## Implementation Timeline

| Date | Item | Status |
|------|------|--------|
| 2026-08-17 | Audit versions (`just audit-versions`) | ✅ Implemented |
| 2026-08-17 | Check flake.lock age (`just check-flake-lock-age`) | ✅ Implemented |
| 2026-08-17 | Audit transitive deps (`audit-transitive-deps.sh`) | ✅ Implemented |
| 2026-08-17 | GitHub Actions workflows (audit-versions.yaml) | ✅ Implemented |
| 2026-08-17 | GitHub Actions workflows (check-flake-lock-age.yaml) | ✅ Implemented |
| 2026-08-17 | GitHub Actions workflows (audit-transitive-deps.yaml) | ✅ Implemented |
| 2026-08-17 | Pre-commit hook (version-consistency) | ✅ Implemented |

---

## Future Enhancements

### Dependency Graph Visualization
Build a `nix-tree` report that shows the full dependency chain and helps identify which packages depend on breaking libraries.

### Binary Cache Invalidation Alerts
Alert when key packages drop out of the binary cache (slower rebuilds incoming).

### License Audit
Periodically scan for license changes in dependencies (compliance).

### Security Advisory Integration
Auto-flag packages with known CVEs in nixpkgs.

---

## Troubleshooting

### "device not found" when pushing
YubiKey SSH signing issue. Plug in the key and try again: `jj git push`

### Audit returns "unknown" versions
The package doesn't exist in that nixpkgs revision (or is conditional). This is safe to ignore.

### Workflow artifacts are empty
Check the workflow run logs — the script may have failed on package evaluation. This usually means a package was removed or renamed in nixpkgs.

---

See also: [CI-HARDENING-RECOMMENDATIONS.md](../CI-HARDENING-RECOMMENDATIONS.md)
