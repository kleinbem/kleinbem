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

# --override-input for every repo. Checks $ROOT/<repo>, then sibling org directories
# (such as $ROOT/../kleinbem-dev/<repo>).
OVERRIDES := shell("bash -c 'root=\"" + ROOT + "\"; sed -nE \"s/^[[:space:]]*\\\"?([a-zA-Z0-9_.-]+)\\\"?[[:space:]]*=[[:space:]]*\\\"([^\\\"]+)\\\".*/\\\\1 \\\\2/p\" \"$root/kleinbem/repos.nix\" 2>/dev/null | while read -r r url; do [ -z \"$r\" ] && continue; url=\"${url#git@github.com:}\"; url=\"${url#https://github.com/}\"; url=\"${url%.git}\"; org=\"${url%%/*}\"; reponame=\"${url#*/}\"; if [ -d \"$root/$r\" ]; then p=\"$root/$r\"; elif [ -n \"$org\" ] && [ \"$org\" != \"kleinbem\" ] && [ -d \"$root/../$org/$reponame\" ]; then p=\"$root/../$org/$reponame\"; elif [ -n \"$org\" ] && [ \"$org\" != \"kleinbem\" ] && [ -d \"$root/../$org/$r\" ]; then p=\"$root/../$org/$r\"; else p=\"$root/$r\"; fi; printf \" --override-input %s git+file://%s\" \"$r\" \"$p\"; done' 2>/dev/null")

KEEP := "3"
TIMER := "time "
LOCK_FILE := "/tmp/kleinbem-workspace-just.lock"
# Non-blocking lock command wrapper for better error messages
LOCK_CMD := "bash -c 'if ! flock -n 9; then echo \"❌ ERROR: Workspace locked by another process at " + LOCK_FILE + ". Run \\`just maintenance::who\\` to check.\"; exit 1; fi; \"$@\"' 9>>" + LOCK_FILE + " -- "
