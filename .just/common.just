# --- Shared Variables ---
# Canonical copy: nix/.just/common.just and openwrt/.just/common.just are
# symlinks to this file. No domain split: one flat list of every repo in repos.nix.

# Workspace root. Callers are a conductor one level below it, or the root
# justfile (a symlink; just uses the symlink's directory). The root has
# kleinbem/repos.nix below it and no .jj; the .jj check matters because nix/
# has a kleinbem -> ../kleinbem symlink. jj-fleet.sh's find_root() walks up instead.
ROOT := shell("d=\"" + justfile_directory() + "\"; while [ \"$d\" != \"/\" ]; do if [ -f \"$d/kleinbem/repos.nix\" ] && [ ! -d \"$d/.jj\" ]; then printf '%s' \"$d\"; exit 0; fi; d=\"$(dirname \"$d\")\"; done; echo ''")

# Every repo in kleinbem/repos.nix; the default scope of every fan-out recipe.
ALL_REPOS := shell("nix eval --raw --file " + ROOT + "/kleinbem/repos.nix --apply 'rs: builtins.concatStringsSep \" \" (builtins.attrNames rs)' 2>/dev/null || echo ''")

# Alias still used by nix/ and openwrt/ maintenance.just and ai.just.
REPOS := ALL_REPOS

# --override-input for every repo. A name that isn't an input of the flake only
# warns ("does not match any input"). | is the sed delimiter because ROOT has slashes.
# The extra nix-secrets -> kleinbem-secrets mapping is for the old input name;
# no flake uses it any more (nix-config's input is kleinbem-secrets).
OVERRIDES := shell("echo '" + ALL_REPOS + "' | tr ' ' '\\n' | grep -vx nix-secrets | tr '\\n' ' ' | sed -E 's|([^ ]+)|--override-input \\1 git+file://" + ROOT + "/\\1|g'") + " --override-input nix-secrets git+file://" + ROOT + "/kleinbem-secrets"

KEEP := "3"
TIMER := "time "
LOCK_FILE := "/tmp/kleinbem-workspace-just.lock"
# Non-blocking lock command wrapper for better error messages
LOCK_CMD := "bash -c 'if ! flock -n 9; then echo \"❌ ERROR: Workspace locked by another process at " + LOCK_FILE + ". Run \\`just maintenance::who\\` to check.\"; exit 1; fi; \"$@\"' 9>>" + LOCK_FILE + " -- "
