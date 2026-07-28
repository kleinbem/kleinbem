# Fleet-Wide Hub — kleinbem/ is the workspace root/profile repo, and the one
# place the jj dashboard operates on EVERY repo by default (nix/ and openwrt/
# each default to their own domain — see kleinbem/.just/common.just).
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
save-all message="" filter="":
    @just jj::save-all "{{message}}" {{filter}}

[group("Main")]
ship-all message="" filter="":
    @just jj::ship-all "{{message}}" {{filter}}

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

# Pass-through to any repo's own justfile from the workspace root.
# Usage:
#   just in nix-config nixos::switch
#   just in openwrt-config check core-gateway
[group("Main")]
in repo *args:
    @cd {{ROOT}}/{{repo}} && just {{args}}

# Unit tests for the shared tooling (tools/resolve-targets.sh,
# tools/domain-scope.nix) — the logic nix/ and openwrt/ both depend on via
# symlink. Fast, no side effects on any real repo. Run after touching
# anything in .just/ or tools/.
[group("Main")]
test:
    #!/usr/bin/env bash
    set -e
    failed=0
    for t in {{ROOT}}/kleinbem/tests/test-*.sh; do
        echo "── $(basename "$t") ──"
        bash "$t" || failed=1
        echo
    done
    exit $failed
