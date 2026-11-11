# Architecture Decision Record: Platform-Specific Tooling

**Title:** Disable waypipe on aarch64-linux; x86_64-only for remote GUI forwarding  
**Date:** 2026-08-17  
**Status:** Implemented  
**Supersedes:** None  

---

## Context

**Problem:** waypipe 0.11.0 fails to build on aarch64-linux due to FFmpeg 9.0 API changes in Vulkan device context structures. This breaks the entire "Build & Cache All" CI job for Orin Nano (aarch64).

**Constraints:**
- waypipe is included fleet-wide in `core.nix` (shared module)
- aarch64 devices (orin-nano, core-pi, hass-pi) are all headless
- x86_64 devices (mac-mini, nixos-nvme) benefit from waypipe for remote Wayland forwarding
- No waypipe alternative for x86_64 workstations (GNOME Remote Desktop doesn't forward individual apps)

---

## Decision

**Conditionally exclude waypipe from aarch64-linux systems while keeping it on x86_64.**

```nix
# modules/nixos/core.nix - environment.systemPackages

++ lib.optionals (pkgs.stdenv.hostPlatform.system != "aarch64-linux") [
  waypipe
]
```

---

## Rationale

### Why Not Fix waypipe?

1. **Complexity:** Patching waypipe for FFmpeg 9.0 requires understanding FFmpeg's new Vulkan queue family API
2. **Maintenance burden:** waypipe is small/niche; nixpkgs community unlikely to backport quickly
3. **Usage:** Only x86_64 workstations actually use it (for SSH remote GUI forwarding)

### Why Not Downgrade FFmpeg?

1. **Loses improvements:** FFmpeg 9.0 has security fixes and performance improvements
2. **Ripple effects:** Downgrading FFmpeg impacts other packages; testing burden high
3. **Temporary:** FFmpeg will keep advancing; better to address root problem

### Why This Solution?

1. **Minimal:** One-liner conditional; no API changes or versioning logic
2. **Correct:** aarch64 devices are headless by design; they don't need Wayland forwarding
3. **Future-proof:** If aarch64 gains a desktop later, just remove the conditional
4. **No regression:** x86_64 builds unaffected; waypipe still available where it's used

---

## Alternatives Considered

### A. Upgrade waypipe to newer version
**Decision:** ❌ Rejected  
- nixpkgs still uses 0.11.0 (current version as of 2026-08-17)
- No newer stable release available

### B. Patch waypipe FFmpeg 9.0 compatibility
**Decision:** ❌ Rejected  
- High effort for niche package
- No one else maintaining the patch

### C. Remove waypipe everywhere
**Decision:** ❌ Rejected  
- mac-mini (x86_64) sometimes uses waypipe for remote app debugging
- GNOME Remote Desktop streams the whole desktop, not individual apps

### D. Create waypipe-free NixOS module for aarch64
**Decision:** ❌ Rejected  
- Splits core.nix by platform; maintenance burden
- Current solution is simpler (one conditional)

---

## Implementation

### Files Modified
- `nix-config/modules/nixos/core.nix` - Conditional waypipe inclusion

### Affected Systems
- **x86_64-linux:** ✓ Waypipe still included
  - mac-mini: Available for SSH remote Wayland forwarding
  - nixos-nvme: Available for debugging
- **aarch64-linux:** ✗ Waypipe excluded
  - orin-nano: Headless; no GUI needed
  - core-pi: Headless; no GUI needed
  - hass-pi: Headless; no GUI needed

### Testing
```bash
# Verify waypipe excluded on aarch64
nix eval '.#nixosConfigurations.orin-nano.config.environment.systemPackages' | grep -i waypipe  # Should be empty

# Verify waypipe included on x86_64
nix eval '.#nixosConfigurations.mac-mini.config.environment.systemPackages' | grep -i waypipe  # Should match
```

---

## Consequences

### Positive
- ✅ Unblocks aarch64 CI builds
- ✅ No impact to x86_64 workstations
- ✅ Future-proof (easy to revert if headless→desktop migration happens)
- ✅ Minimal code change (one conditional)

### Negative
- ⚠️ If aarch64 ever gains a desktop GUI, must be added back to core.nix
- ⚠️ Adds platform-specific logic to shared module (but acceptable for this edge case)

---

## Related Decisions

**See also:**
- GNOME Remote Desktop setup (mac-mini) - primary RDP solution now
- Waypipe usage history - was backup/debugging tool for mac-mini pre-GRD
- Fleet architecture - intentional separation of headless (aarch64) vs. desktop (x86_64)

---

## Lessons Learned

1. **Version pinning:** Transitive C library API breakages (FFmpeg) can cascade into unexpected build failures
2. **Platform-specific tooling:** Some tools are x86_64-only by necessity (Wayland forwarding over SSH); acknowledge this in architecture
3. **CI stability:** Conditional inclusions based on build platform help avoid cross-arch surprises

---

**Approved by:** User (via workflow audit 2026-08-17)  
**Implementation date:** 2026-08-17 (awaiting push)  
**Review date:** 2026-12-17 (check if FFmpeg 10+ resolves waypipe compatibility)
