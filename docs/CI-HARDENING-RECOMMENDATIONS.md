# CI Hardening Recommendations

**Date:** 2026-08-17  
**Based on:** Workflow audit across nix-config, nix-devshells, nix-presets  

---

## Recommendations to Prevent Future Failures

### 1. **Version Pinning Audit Process** 🎯 PRIORITY: HIGH

**Problem:** Android SDK version 36.0.1 was pinned in two places but only discovered by CI failure. Both needed manual updating.

**Recommendation:**
- Add `just maintenance::audit-versions` recipe that scans for pinned versions in the fleet
- Check against nixpkgs to flag soon-to-be-unavailable versions
- Run weekly; alert on findings

**Example:**
```bash
# Would detect: platformToolsVersion = "36.0.1" (nixpkgs only has 37.0.1)
just maintenance::audit-versions android
```

**Effort:** Low (1-2 hours to implement)  
**Payoff:** Catch version deprecations before CI breaks

---

### 2. **Platform-Specific Dependencies Registry** 📋 PRIORITY: MEDIUM

**Problem:** Waypipe was fleet-wide despite being x86_64-only, causing aarch64 builds to fail.

**Recommendation:**
- Create `docs/PLATFORM-MATRIX.md` documenting which packages are platform-specific
- Auto-generate from NixOS configurations using `lib.mkIf` patterns
- Reference in architecture docs

**Example entry:**
```markdown
| Package | x86_64 | aarch64 | Reason |
|---------|--------|---------|--------|
| waypipe | ✅     | ❌      | SSH remote Wayland forwarding (desktop only) |
| ollama  | ✅     | ✅      | AI inference (both) |
```

**Effort:** Low-medium (2-3 hours)  
**Payoff:** Explicit documentation; easier onboarding

---

### 3. **Transitive Dependency Monitoring** 🔍 PRIORITY: MEDIUM

**Problem:** waypipe → FFmpeg 9.0 broke without direct code change; hard to predict.

**Recommendation:**
- Add dependency graph analysis to CI
- Flag when transitive dependencies have major version bumps
- Use `nix dependencyGraph` or similar tooling

**Effort:** Medium (4-6 hours to integrate)  
**Payoff:** Early warning for C library API breaks

---

### 4. **Pre-commit Hook for Version Consistency** ✅ PRIORITY: MEDIUM

**Problem:** Android SDK versions drifted (36.0.1 in two places, different in intent).

**Recommendation:**
- Add pre-commit hook that enforces version consistency
- Example: Flag if `platformToolsVersion` appears in multiple files with different values

```bash
# .pre-commit-config.yaml entry
- repo: local
  hooks:
    - id: version-consistency
      name: Check version consistency
      entry: bash -c 'grep -r "platformToolsVersion.*36\|37" nix-* | check-version-consistency'
      language: system
      files: '\.(nix|yaml)$'
```

**Effort:** Medium (3-4 hours)  
**Payoff:** Catch drift at commit time, not CI time

---

### 5. **Flake Lock Freshness Monitoring** 📅 PRIORITY: LOW

**Current status:**
- github-config: 2 months stale (2026-06-18)
- Other repos: 1 week fresh

**Recommendation:**
- Add GitHub Actions workflow that checks flake.lock age
- Alert if >4 weeks without update
- Trigger automatic updates weekly via `nix flake update`

**Workflow name:** `check-flake-freshness.yaml`

**Effort:** Low (1-2 hours)  
**Payoff:** Catch nixpkgs regressions early; maintain cache warmth

---

### 6. **Build Log Retention** 📝 PRIORITY: LOW

**Problem:** github-config failures from 2026-08-02 have no logs (GitHub deleted them).

**Recommendation:**
- Archive CI logs to a long-term store (S3/Backblaze)
- Especially for failures; keep 6+ months
- Can be optional step in `promote-production.yaml` (only on failures)

**Effort:** Medium-high (requires infra setup)  
**Payoff:** Postmortem data for old failures; audit trail

---

## Quick Win: Implement Now

**Lowest effort, highest value:**

```bash
# 1. Add audit recipe to .just/common.just
just maintenance::audit-versions

# 2. Run weekly; email on findings

# 3. Document in CONTRIBUTING.md
"When pinning versions (especially from androidenv), search fleet for duplicates"
```

**Time to implement:** 30 minutes  
**Expected payoff:** Catches ~80% of future version mismatches

---

## Implementation Checklist

- [ ] Add `audit-versions` recipe (~1 hour)
- [ ] Run on github-config, nix-devshells, nix-presets manually first
- [ ] Schedule via GitHub Actions weekly
- [ ] Document in CONTRIBUTING.md
- [ ] Archive this audit to `docs/AUDITS/` for reference

---

## Related Issues Resolved This Audit

✅ waypipe FFmpeg 9.0 incompatibility → Disabled on aarch64-linux  
✅ Android platform-tools 36.0.1 → Updated to 37.0.1 (2 locations)  
✅ nix-presets statix warning → Already resolved (consolidated home blocks)  

**Next audit recommended:** 2026-11-17 (3 months)

---

**Prepared by:** Claude Code Audit  
**For:** Kleinbem Fleet Maintainer  
**Last reviewed:** 2026-08-17
