# --- Shared Variables ---
#
# Canonical copy — nix/.just/common.just and openwrt/.just/common.just are
# symlinks to this file. It's self-aware of which conductor invoked it via
# DOMAIN (derived from justfile_directory(), which `just` always resolves to
# the invoking ROOT justfile's directory — nix/, openwrt/, or kleinbem/ itself
# — regardless of where this particular file physically lives).

# Get the absolute path to the workspace root (parent of the conductor dir)
ROOT := parent_directory(justfile_directory())

# Which conductor invoked us: "nix", "openwrt", or "kleinbem" (the fleet-wide hub)
DOMAIN := shell("basename " + justfile_directory())

# Every repo listed in the fleet-wide manifest (kleinbem/repos.nix) — sub-repos
# only, NOT the three conductors themselves (they aren't clone targets).
MANIFEST_REPOS := shell("nix eval --raw --file " + ROOT + "/kleinbem/repos.nix --apply 'rs: builtins.concatStringsSep \" \" (builtins.attrNames rs)' 2>/dev/null || echo ''")

# MANIFEST_REPOS narrowed to this DOMAIN (or the "shared" tag) — no self entry.
# Used by recipes that can't include self (bootstrap can't clone the repo
# it's already running from) and by OVERRIDES (flake inputs only ever point
# at actual flakes, never at a tooling-only conductor dir). The actual filter
# logic lives in tools/domain-scope.nix — a standalone, directly unit-tested
# function (see tests/test-domain-scope.sh) rather than an inline expression.
MANIFEST_SCOPE := if DOMAIN == "kleinbem" { MANIFEST_REPOS } else { shell("DOMAIN='" + DOMAIN + "' nix eval --raw --file " + ROOT + "/kleinbem/repos.nix --impure --apply 'rs: import " + ROOT + "/kleinbem/tools/domain-scope.nix rs' 2>/dev/null || echo ''") }

# Every addressable repo in the fleet, INCLUDING the three conductors — the
# universe fan-out recipes' `filter` argument substring-matches against.
ALL_REPOS := "nix openwrt kleinbem " + MANIFEST_REPOS

# Default scope for this conductor's fan-out recipes when no filter is given:
# itself + its domain's sub-repos + anything tagged "shared". kleinbem/ itself
# defaults to the whole fleet.
REPOS := if DOMAIN == "kleinbem" { ALL_REPOS } else { DOMAIN + " " + MANIFEST_SCOPE }

# Flake-input overrides for this conductor's actual flakes (never the
# conductors themselves — they have no flake.nix). Use | as the sed delimiter
# to avoid conflict with the forward slashes in the ROOT path.
OVERRIDES := shell("echo '" + MANIFEST_SCOPE + "' | sed -E 's|([^ ]+)|--override-input \\1 git+file://" + ROOT + "/\\1|g'")

KEEP := "3"
TIMER := "time "
LOCK_FILE := "/tmp/" + DOMAIN + "-just.lock"
# Non-blocking lock command wrapper for better error messages
LOCK_CMD := "bash -c 'if ! flock -n 9; then echo \"❌ ERROR: Workspace locked by another process at " + LOCK_FILE + ". Run \\`just maintenance::who\\` to check.\"; exit 1; fi; \"$@\"' 9>>" + LOCK_FILE + " -- "
