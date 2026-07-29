# --- Shared Variables ---
#
# Canonical copy — nix/.just/common.just and openwrt/.just/common.just are
# symlinks to this file.
#
# No domain concept: one flat list of every repo in kleinbem/repos.nix,
# including the three former "conductors" (nix, openwrt, kleinbem) as regular
# entries. Nothing here is nix-specific or openwrt-specific.

# Get the absolute path to the workspace root (parent of the conductor dir).
# Only valid for files living exactly one level below the root (nix/,
# openwrt/, kleinbem/) — see kleinbem/tools/jj-fleet.sh's find_root() for the
# general walk-up version used everywhere else (works from any depth).
ROOT := parent_directory(justfile_directory())

# Every repo in the fleet-wide manifest (kleinbem/repos.nix) — flat, no
# categorization. Used as-is: no per-conductor default scope anymore, every
# fan-out recipe's default (no filter) is "every repo".
ALL_REPOS := shell("nix eval --raw --file " + ROOT + "/kleinbem/repos.nix --apply 'rs: builtins.concatStringsSep \" \" (builtins.attrNames rs)' 2>/dev/null || echo ''")

# Kept as a plain alias so maintenance.just/ai.just (not part of this round's
# redesign, still reference {{REPOS}} for their own format-all/lint-all/
# knowledge-sync loops) get the same "whole fleet" behavior consistently,
# rather than half the tooling being domain-less and half not. Those loops
# are already guarded (skip if no flake.nix / no tracked *.sh files), so this
# is a low-risk, honest side-effect rather than a silent behavior change.
REPOS := ALL_REPOS

# Flake-input overrides — every repo gets one, including non-flakes (nix,
# openwrt, kleinbem, github-config, kleinbem-secrets); nix silently ignores
# --override-input for names that aren't actual flake inputs, so this is
# harmless rather than worth filtering. Use | as the sed delimiter to avoid
# conflict with the forward slashes in the ROOT path.
OVERRIDES := shell("echo '" + ALL_REPOS + "' | sed -E 's|([^ ]+)|--override-input \\1 git+file://" + ROOT + "/\\1|g'")

KEEP := "3"
TIMER := "time "
LOCK_FILE := "/tmp/kleinbem-workspace-just.lock"
# Non-blocking lock command wrapper for better error messages
LOCK_CMD := "bash -c 'if ! flock -n 9; then echo \"❌ ERROR: Workspace locked by another process at " + LOCK_FILE + ". Run \\`just maintenance::who\\` to check.\"; exit 1; fi; \"$@\"' 9>>" + LOCK_FILE + " -- "
