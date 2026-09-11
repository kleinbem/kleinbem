# Kleinbem Fleet Maintenance Runbooks

**Updated:** 2026-08-17  
**Audience:** Fleet maintainers  

Quick reference guides for common maintenance tasks across the kleinbem fleet.

---

## Quick Reference

| Task | Command | When | Duration |
|------|---------|------|----------|
| Check version freshness | `just audit-versions` | Weekly | 2 min |
| Check flake lock age | `just check-flake-lock-age` | Weekly | 1 min |
| Update stale flake.lock | `just in <repo> flake update` | When >30 days old | 5-10 min |
| Rebuild host after update | `just in <repo> nixos::switch` | After config changes | 15-60 min |
| Check CI status | `just remote-ci 10` | Before pushing | 1 min |

---

## Task 1: Handle Deprecated Package Versions

**Symptom:** CI failure with "Version X.Y.Z is missing in package FOO"

**Root Cause:** Package pinned to version no longer available in nixpkgs

**Example:** Android platform-tools 36.0.1 → 37.0.1 (Aug 2026)

### Step 1: Identify the Problem

```bash
# Run from workspace root
just audit-versions android
# Output: shows platform-tools version pinned in nix-devshells and nix-presets
```

### Step 2: Find All Occurrences

```bash
grep -r "platformToolsVersion.*36" nix-* --include="*.nix"
# Returns all locations where version is pinned
```

### Step 3: Check Latest Available Version

```bash
# Option A: Check GitHub/upstream
# Option B: Let nixpkgs tell you (run build, see what versions are available)
# Option C: Search NixOS package search: https://search.nixos.org
```

### Step 4: Update All Locations

```bash
# Must update EVERY location consistently
nix-devshells/shells/android.nix:        platformToolsVersion = "37.0.1";
nix-presets/nixosModules/android-emulator.nix:  platformToolsVersion = "37.0.1";
```

### Step 5: Test & Commit

```bash
cd nix-devshells && nix flake check  # Verify build succeeds
cd ../nix-presets && nix flake check

# Commit both repos
git commit -m "fix: update Android platform-tools to 37.0.1"
```

### Prevention for Next Time

- [ ] Add `just audit-versions` to your weekly maintenance schedule
- [ ] Watch for warning signs in CI (Maintain Flake jobs)
- [ ] Update BOTH locations if android SDK changes

---

## Task 2: Handle Transitive Dependency Breaks

**Symptom:** Build fails with "no field `X` on type `Y`" or similar C API errors

**Root Cause:** Transitive C library update (e.g., FFmpeg 8 → 9) broke downstream package

**Example:** waypipe + FFmpeg 9.0 (Aug 2026)

### Step 1: Identify the Breaking Change

```bash
# From CI logs or local build
error[E0609]: no field `queue_family_tx_index` on type `&mut AVVulkanDeviceContext`
# This tells you: waypipe uses a field that FFmpeg 9.0 removed
```

### Step 2: Assess Impact

```bash
# Questions to answer:
1. Is this package platform-specific?
   - If x86_64-only: Can conditionally exclude it
   - If universal: Must fix or downgrade upstream library

2. Is there a newer version of the downstream package?
   - Check GitHub/nixpkgs for newer waypipe releases
   
3. Can we downgrade the upstream library?
   - Check if downgrade breaks other packages
```

### Step 3: Choose Resolution Strategy

**Option A: Conditionally exclude (if x86_64-only)**
```nix
# If package only needed on certain platforms
++ lib.optionals (pkgs.stdenv.hostPlatform.system != "aarch64-linux") [
  waypipe
]
# Pro: Minimal change; unblocks CI
# Con: Feature unavailable on that platform
```

**Option B: Wait for downstream update**
```bash
# If newer version available in nixpkgs
nixpkgs has waypipe 0.12.0 with FFmpeg 9.0 support
# Pro: Full fix; all platforms work
# Con: Requires nixpkgs update cycle
```

**Option C: Downgrade upstream (last resort)**
```nix
# Force older FFmpeg version for this package only
waypipe = pkgs.waypipe.override { ffmpeg = pkgs.ffmpeg_8; };
# Pro: Works without changes
# Con: Reduces security/perf improvements for everything else
```

### Step 4: Implement & Test

```bash
# For Option A (conditional)
# Edit: nix-config/modules/nixos/core.nix
lib.optionals (pkgs.stdenv.hostPlatform.system != "aarch64-linux") [
  waypipe
]

# Test the affected platform
nix eval '.#nixosConfigurations.orin-nano.config.environment.systemPackages' | grep waypipe
# Should be empty (waypipe excluded on aarch64)
```

---

## Task 3: Refresh Stale Flake Locks

**Symptom:** `check-flake-lock-age` shows repo >30 days old

**When:** Usually safe; check for breaking changes first

### Step 1: Check Current Status

```bash
just check-flake-lock-age
# Shows which repos need updates (>30 days)
```

### Step 2: Backup Before Update

```bash
cd target-repo
git stash  # Save any uncommitted work
cp flake.lock flake.lock.backup
```

### Step 3: Update & Test

```bash
nix flake update  # Fetch latest from all inputs

# Quick sanity check
nix flake check --override-input nix-devshells github:kleinbem/nix-devshells
# or for nixos configs:
nix eval '.#nixosConfigurations.mac-mini'

# If error, revert:
cp flake.lock.backup flake.lock
```

### Step 4: Review & Commit

```bash
git diff flake.lock  # Review what changed

# Commit with context
git commit -m "chore: update flake.lock ($(date +%Y-%m-%d))

Updated inputs: nixpkgs, home-manager, ...
No breaking changes detected.
"
```

### Troubleshooting: What if Update Breaks?

```bash
# Common issue: nixpkgs has removed/deprecated a package
# Solution: Either find replacement or pin to older nixpkgs

# Pin nixpkgs to commit before breaking change
nix flake update --override-input nixpkgs github:NixOS/nixpkgs/COMMIT_SHA
```

---

## Task 4: Investigate CI Failures

**When:** A workflow turns red unexpectedly

### Step 1: Categorize the Failure

```bash
# Check the job type
just remote-ci 10  # See recent runs

# Failure patterns:
- "Build & Cache All (Fast)" → Build failed (see build logs)
- "Maintain Flake" → Scheduled update failed (usually version issues)
- "Check Flake" → Linting/validation failed (nixfmt, statix)
- "Terraform Apply" → IaC deployment failed
```

### Step 2: Read the Logs

```bash
# GitHub Actions → Click run → View logs
# Key sections to check:
1. "Fetching the repository" — git checkout issues?
2. "Run nix flake check" — evaluation/parsing errors?
3. "error:" at the end — actual failure message

# For transitive breaks (FFmpeg, etc.):
# Look for "no field" or "undefined" in compiler output
```

### Step 3: Reproduce Locally

```bash
# If possible, reproduce the exact failure locally
cd nix-config
nix flake check --show-trace  # More verbose error

# If cross-platform (e.g., aarch64 build on x86_64):
nix build '.#nixosConfigurations.orin-nano' --system aarch64-linux
```

### Step 4: Fix & Verify

```bash
# Make the fix (see tasks above)
# Run the same check that failed:
nix flake check

# If it passed, commit and push
git commit -m "fix: <issue>"
# Wait for YubiKey, then: git push origin main
```

---

## Task 5: Safe Flake.lock Refresh During Merge Conflicts

**When:** Multiple repos updated flake.lock simultaneously

### The Problem

```bash
# Scenario: You fetch latest changes, but flake.lock has merge conflict
# Because you also updated flake.lock locally
```

### Safe Resolution

```bash
# DO NOT resolve manually; let Nix do it
git status  # Shows conflict in flake.lock

# Option A: Prefer remote (they just updated it)
git checkout --theirs flake.lock
nix flake update  # Reconcile with local inputs if any

# Option B: Prefer local (you have recent changes)
git checkout --ours flake.lock
nix flake update  # Ensure consistency

# Then:
git add flake.lock
git commit -m "resolve flake.lock merge conflict"
nix flake check  # Verify the result
```

---

## Task 6: Monitor Health Between Audits

**Cadence:** Weekly

```bash
# Monday morning ritual
just audit-versions
just check-flake-lock-age
just remote-ci 5  # Recent runs green?

# Any warnings? Plan fixes for mid-week updates.
```

---

## Common Mistakes to Avoid

### ❌ Don't

- Update only one copy of a pinned version (like android SDK)
  - ✅ Do: Search entire fleet, update all occurrences

- Commit flake.lock without testing locally first
  - ✅ Do: Run `nix flake check` before committing

- Resolve flake.lock conflicts by hand
  - ✅ Do: Use `git checkout --ours/--theirs`, then `nix flake update`

- Ignore "Maintain Flake" failures thinking they're transient
  - ✅ Do: Investigate; they usually indicate version/deprecation issues

- Downgrade transitive dependencies without considering security impact
  - ✅ Do: Check release notes for why the new version exists

---

## Escalation Path

**If you get stuck:**

1. **Reproducible locally?** → Likely your code issue (see Task 4)
2. **CI-only failure?** → Likely platform-specific (see Task 2)
3. **Multiple repos failing identically?** → Fleet-wide issue (check common inputs)
4. **In doubt?** → Consult audit docs: `WORKFLOW_AUDIT_2026-08-17.md`

---

## Related Documentation

- `PLATFORM-MATRIX.md` - Which packages go where
- `ADR-WAYPIPE-PLATFORM-SEPARATION.md` - Architecture decisions
- `CI-HARDENING-RECOMMENDATIONS.md` - Prevent future issues

---

**Last Updated:** 2026-08-17  
**Next Review:** 2026-11-17 (quarterly)
