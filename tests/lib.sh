#!/usr/bin/env bash
# Shared assertion helpers for kleinbem/tests/*.sh. Source this, run your
# assert_* calls, then call test_summary at the end — it prints the tally
# and exits non-zero if anything failed (so `just test` fails loudly).
#
# Not a framework — this workspace doesn't otherwise depend on one (bats
# etc. aren't in nix-devshells), and the test surface here is small enough
# that a hand-rolled ~30-line helper is less overhead than adding one.

_PASS=0
_FAIL=0

# assert_eq <expected> <actual> <description>
assert_eq() {
    local expected="$1" actual="$2" desc="$3"
    if [ "$expected" = "$actual" ]; then
        _PASS=$((_PASS + 1))
        printf '  \033[32m✓\033[0m %s\n' "$desc"
    else
        _FAIL=$((_FAIL + 1))
        printf '  \033[31m✗\033[0m %s\n' "$desc"
        printf '      expected: %q\n' "$expected"
        printf '      actual:   %q\n' "$actual"
    fi
}

# assert_empty <actual> <description>
assert_empty() {
    assert_eq "" "$1" "$2"
}

test_summary() {
    echo
    if [ "$_FAIL" -eq 0 ]; then
        printf '\033[32m✅ %d/%d passed\033[0m\n' "$_PASS" "$((_PASS + _FAIL))"
        exit 0
    else
        printf '\033[31m❌ %d/%d passed, %d failed\033[0m\n' "$_PASS" "$((_PASS + _FAIL))" "$_FAIL"
        exit 1
    fi
}
