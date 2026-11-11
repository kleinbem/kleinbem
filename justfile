# Fleet hub. Fan-out recipes default to the whole fleet, the same from nix/,
# openwrt/ or the workspace root (whose justfile is a symlink to root/justfile).
import '.just/common.just'

# --- Modules ---
mod jj '.just/jj.just'

[group("Main")]
default:
    @just jj::hub

[group("Main")]
status-all filter="":
    @just jj::status-all {{filter}}

[group("Main")]
clean *args="":
    @just jj::clean {{args}}

[group("Main")]
abandon-merged *args="":
    @just jj::abandon-merged {{args}}

[group("Main")]
save-all message="" filter="":
    @just jj::save-all {{quote(message)}} {{filter}}

[group("Main")]
ship-all message="" filter="":
    @just jj::ship-all {{quote(message)}} {{filter}}

alias ship := ship-all

[group("Main")]
diff-all filter="" *args="":
    @just jj::diff-all {{filter}} {{args}}

[group("Main")]
pull-all filter="":
    @just jj::pull-all {{filter}}

[group("Main")]
push-all filter="":
    @just jj::push-all {{filter}}

[group("Main")]
sign-unsigned filter="":
    @just jj::sign-unsigned {{filter}}

[group("Main")]
bootstrap filter="":
    @just jj::bootstrap {{filter}}

[group("Main")]
sync-agent-links filter="":
    @just jj::sync-agent-links {{filter}}

[positional-arguments]
[group("Main")]
agent repo name="" runner="claude" *args:
    @just jj::agent "$@"

# Pass-through to any repo's own justfile from the workspace root.
# Usage:
#   just in nix-config nixos::switch
#   just in openwrt-config check core-gateway
[group("Main")]
in repo *args:
    #!/usr/bin/env bash
    set -euo pipefail
    # repo-path also finds repos under sibling orgs (kleinbem-dev/<repo>).
    dir="$(ROOT="{{ROOT}}" bash "{{ROOT}}/kleinbem/tools/jj-fleet.sh" repo-path "{{repo}}")"
    cd "$dir"
    exec just {{args}}

# Unit tests for the shared tooling in tools/; fast, touches no real repo.
[group("Main")]
test:
    #!/usr/bin/env bash
    set -e
    failed=0
    # This checkout's own tests, so agent workspaces test their changes.
    for t in {{justfile_directory()}}/tests/test-*.sh; do
        echo "── $(basename "$t") ──"
        bash "$t" || failed=1
        echo
    done
    exit $failed
