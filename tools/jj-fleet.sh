#!/usr/bin/env bash
# jj-fleet — Nix-packaged subset of the jj dashboard (kleinbem/flake.nix,
# writeShellApplication: pinned runtimeInputs + shellcheck-gated build).
#
# Covers the read-only/safe recipes only: status-all, diff-all,
# remote-status, remote-prs, remote-ci, check-signatures, bootstrap,
# init-bookmarks. Everything with real mutation logic (save-all, push-all,
# ship-all, sign-unsigned, ...) is still in kleinbem/.just/jj.just, converted
# later once this phase proves out.
#
# Run FROM the conductor directory (nix/, openwrt/, kleinbem/) whose default
# scope you want, same convention as `just`. When invoked via the `just`
# wrappers in jj.just, ROOT/DOMAIN are passed explicitly as env vars (jj.just
# runs with cwd=.just/, not the conductor dir, so $PWD alone isn't reliable
# there); direct human invocation falls back to $PWD.
#
# Usage: jj-fleet <subcommand> [args...]
set -euo pipefail

ROOT="${ROOT:-$(dirname "$PWD")}"
DOMAIN="${DOMAIN:-$(basename "$PWD")}"

MANIFEST_REPOS=$(nix eval --raw --file "$ROOT/kleinbem/repos.nix" \
    --apply 'rs: builtins.concatStringsSep " " (builtins.attrNames rs)' 2>/dev/null || true)

if [ "$DOMAIN" = "kleinbem" ]; then
    MANIFEST_SCOPE="$MANIFEST_REPOS"
else
    MANIFEST_SCOPE=$(DOMAIN="$DOMAIN" nix eval --raw --file "$ROOT/kleinbem/repos.nix" --impure \
        --apply "rs: import $ROOT/kleinbem/tools/domain-scope.nix rs" 2>/dev/null || true)
fi

ALL_REPOS="nix openwrt kleinbem $MANIFEST_REPOS"
if [ "$DOMAIN" = "kleinbem" ]; then
    REPOS="$ALL_REPOS"
else
    REPOS="$DOMAIN $MANIFEST_SCOPE"
fi

resolve_targets() {
    # shellcheck disable=SC2086 # intentional word-splitting of REPOS/ALL_REPOS
    bash "$ROOT/kleinbem/tools/resolve-targets.sh" "$1" $REPOS -- $ALL_REPOS
}

resolve_manifest_targets() {
    # shellcheck disable=SC2086
    bash "$ROOT/kleinbem/tools/resolve-targets.sh" "$1" $MANIFEST_SCOPE -- $MANIFEST_REPOS
}

# --- status-all ---
cmd_status_all() {
    local filter="${1:-}" targets
    targets=$(resolve_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "📊 Workspace Status (jj)"
    {
        printf "REPO\tCHANGE\t@ STATE\tAHEAD OF ORIGIN\n"
        for repo in $targets; do
            local dir="$ROOT/$repo" name="$repo" change empty desc desc_short status_desc described_n undescribed_n ahead
            change=$(cd "$dir" && jj log -r @ --no-graph -T 'change_id.short()' 2>/dev/null)
            empty=$(cd "$dir" && jj log -r @ --no-graph -T 'if(empty, "1", "0")' 2>/dev/null)
            desc=$(cd "$dir" && jj log -r @ --no-graph -T 'description.first_line()' 2>/dev/null)
            desc_short="${desc:0:60}"
            [ "${#desc}" -gt 60 ] && desc_short="${desc_short}…"
            if [ "$empty" = "1" ]; then status_desc="(empty)"
            elif [ -z "$desc" ]; then status_desc="⚠ undescribed"
            else status_desc="📝 $desc_short"; fi
            described_n=$(cd "$dir" && jj log -r 'main@origin..@ & ~empty()' --no-graph -T 'if(description, "1\n", "")' 2>/dev/null | grep -c . || true)
            undescribed_n=$(cd "$dir" && jj log -r 'main@origin..@ & ~empty()' --no-graph -T 'if(description, "", "1\n")' 2>/dev/null | grep -c . || true)
            if [ "$described_n" -eq 0 ] && [ "$undescribed_n" -eq 0 ]; then ahead="(none)"
            elif [ "$undescribed_n" -eq 0 ]; then ahead="📝 $described_n ready"
            elif [ "$described_n" -eq 0 ]; then ahead="⚠ $undescribed_n undescribed"
            else ahead="📝$described_n ⚠$undescribed_n (mixed)"; fi
            printf "%s\t%s\t%s\t%s\n" "$name" "$change" "$status_desc" "$ahead"
        done
    } | column -t -s $'\t'
}

# --- remote-status ---
cmd_remote_status() {
    local filter="${1:-}" targets out
    targets=$(resolve_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "📡 Remote Workspace Status (GitHub)"
    export ROOT targets
    # shellcheck disable=SC2016 # single-quoted on purpose: $targets/$repo/etc are expanded by the child bash -c, not here
    out=$(gum spin --spinner dot --title "Querying GitHub..." --show-output -- bash -c '
        {
            printf "REPO\tMAIN\tCI\tPRs\tISSUES\n"
            for repo in $targets; do
                name="$repo"
                ghrepo="kleinbem/$repo"
                sha=$(git -C "$ROOT/$repo" rev-parse --short origin/main 2>/dev/null || echo "?")
                ci=$(gh run list --repo "$ghrepo" --branch main --limit 1 --json conclusion,status \
                    --jq ".[0] | if .status==\"in_progress\" then \"🔄\" elif .conclusion==\"success\" then \"✅\" elif .conclusion==\"failure\" then \"❌\" elif .conclusion==\"cancelled\" then \"⏹\" else \"?\" end" 2>/dev/null || echo "—")
                prs=$(gh pr list --repo "$ghrepo" --state open --json number --jq "length" 2>/dev/null || echo "?")
                issues=$(gh issue list --repo "$ghrepo" --state open --json number --jq "length" 2>/dev/null || echo "?")
                printf "%s\t%s\t%s\t%s\t%s\n" "$name" "$sha" "$ci" "$prs" "$issues"
            done
        }
    ')
    echo "$out" | gum table -s "$(printf '\t')" --print
}

# --- remote-prs ---
cmd_remote_prs() {
    local filter="${1:-}" targets out n
    targets=$(resolve_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🔀 Open PRs across the workspace"
    export targets
    # shellcheck disable=SC2016 # single-quoted on purpose: $targets/$repo/etc are expanded by the child bash -c, not here
    out=$(gum spin --spinner dot --title "Fetching PRs..." --show-output -- bash -c '
        {
            printf "REPO\t#\tTITLE\tAUTHOR\n"
            for repo in $targets; do
                name="$repo"
                ghrepo="kleinbem/$repo"
                gh pr list --repo "$ghrepo" --state open --json number,title,author \
                    --jq ".[] | \"$name\t#\(.number)\t\(.title)\t@\(.author.login)\"" 2>/dev/null || true
            done
        }
    ')
    n=$(echo "$out" | tail -n +2 | grep -c .)
    if [ "$n" -eq 0 ]; then
        gum style --foreground 46 "✓ No open PRs anywhere."
    else
        echo "$out" | gum table -s "$(printf '\t')" --print
    fi
}

# --- remote-ci ---
cmd_remote_ci() {
    local limit="${1:-5}" filter="${2:-}" targets out
    targets=$(resolve_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🚦 Recent CI runs (last $limit per repo)"
    export targets limit
    # shellcheck disable=SC2016 # single-quoted on purpose: $targets/$repo/etc are expanded by the child bash -c, not here
    out=$(gum spin --spinner dot --title "Fetching CI runs..." --show-output -- bash -c '
        {
            printf "REPO\tSTATUS\tWORKFLOW\tTITLE\n"
            for repo in $targets; do
                name="$repo"
                ghrepo="kleinbem/$repo"
                gh run list --repo "$ghrepo" --limit "$limit" --json conclusion,status,name,displayTitle \
                    --jq ".[] | \"$name\t\(if .status==\"in_progress\" then \"🔄\" elif .status==\"queued\" then \"⏳\" elif .conclusion==\"success\" then \"✅\" elif .conclusion==\"failure\" then \"❌\" elif .conclusion==\"cancelled\" then \"⏹\" elif .conclusion==\"skipped\" then \"⏭\" else \"?\" end)\t\(.name)\t\(.displayTitle)\"" 2>/dev/null || true
            done
        }
    ')
    echo "$out" | gum table -s "$(printf '\t')" --print
}

# --- diff-all ---
cmd_diff_all() {
    local filter="${1:-}"
    shift || true
    local targets any=0
    targets=$(resolve_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🔍 Workspace diff (per-repo, dirty only)"
    for repo in $targets; do
        local name="$repo" dir="$ROOT/$repo"
        if [ -n "$(cd "$dir" && jj diff --summary 2>/dev/null)" ]; then
            any=1
            gum style --foreground 212 --padding "0 1" --margin "1 0 0 0" "📦 $name"
            (cd "$dir" && jj diff "$@")
        fi
    done
    if [ "$any" -eq 0 ]; then
        gum style --foreground 46 --margin "1 0" "✓ Workspace clean — no uncommitted changes anywhere."
    fi
}

# --- check-signatures ---
cmd_check_signatures() {
    local filter="${1:-}" targets any_unsigned=0 any_unverified=0
    targets=$(resolve_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🔐 Signature audit (commits ahead of origin/main)"
    # NOTE: the loop below must NOT be piped directly into gum table — that
    # would run it in a subshell, silently losing any_unsigned/any_unverified
    # (confirmed via shellcheck SC2030/SC2031 while porting this: the
    # currently-shipping .just/jj.just has exactly this bug today — the
    # "unsigned commits found" gate has never actually fired). Accumulate
    # rows in this shell instead, pipe the finished text afterward.
    local rows=("REPO	COMMITS	STATUS	DETAIL")
    for repo in $targets; do
        local name="$repo" dir="$ROOT/$repo" lines unsigned unverified ahead first
        lines=$(git -C "$dir" log --format='%H %G? %s' "origin/main..main" 2>/dev/null || true)
        unsigned=$(echo "$lines" | awk '$2 == "N" || $2 == "B" || $2 == "E"')
        unverified=$(echo "$lines" | awk '$2 == "U" || $2 == "X" || $2 == "Y" || $2 == "R"')
        ahead=$(echo "$lines" | grep -c . || true)
        if [ -n "$unsigned" ]; then
            first=$(echo "$unsigned" | head -1 | awk '{printf "[%s] %s", $2, substr($0, index($0,$3))}')
            rows+=("$(printf '%s\t%s\t%s\t%s' "$name" "$ahead" "❌ UNSIGNED" "$first")")
            any_unsigned=1
        elif [ -n "$unverified" ]; then
            first=$(echo "$unverified" | head -1 | awk '{printf "[%s] %s", $2, substr($0, index($0,$3))}')
            rows+=("$(printf '%s\t%s\t%s\t%s' "$name" "$ahead" "⚠ unverified" "$first")")
            any_unverified=1
        elif [ "$ahead" -eq 0 ] || [ -z "$lines" ]; then
            rows+=("$(printf '%s\t0\t✓ none\t—' "$name")")
        else
            rows+=("$(printf '%s\t%s\t✓ all signed\t—' "$name" "$ahead")")
        fi
    done
    printf '%s\n' "${rows[@]}" | gum table -s "$(printf '\t')" --print
    if [ "$any_unsigned" -eq 1 ]; then
        gum style --foreground 196 --margin "1 0" "🔧 Fix unsigned with: just jj::sign-unsigned"
        exit 1
    elif [ "$any_unverified" -eq 1 ]; then
        gum style --foreground 220 --margin "1 0" "ℹ Unverified ≠ rejected. Push will likely succeed; local mismatch is cosmetic."
    else
        gum style --foreground 46 --margin "1 0" "✅ All ahead-of-origin commits are signed and verified"
    fi
}

# --- bootstrap ---
cmd_bootstrap() {
    local filter="${1:-}" targets
    targets=$(resolve_manifest_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🌱 Bootstrapping workspace from kleinbem/repos.nix"
    for repo in $targets; do
        local rpath="$ROOT/$repo"
        if [ -d "$rpath" ]; then
            gum style --foreground 46 "  ✓ $repo (already cloned)"
        else
            local url
            url=$(nix eval --raw --file "$ROOT/kleinbem/repos.nix" --apply "rs: rs.\"$repo\".url")
            gum spin --spinner dot --title "cloning $repo..." -- bash -c "
                git clone '$url' '$rpath' >/dev/null 2>&1
                cd '$rpath' && jj git init --colocate >/dev/null 2>&1 && jj bookmark track main --remote=origin >/dev/null 2>&1
            "
            gum style --foreground 46 "  ✓ $repo cloned + jj-initialised"
        fi
    done
    gum style --foreground 46 --margin "1 0" "✅ Workspace bootstrapped."
}

# --- init-bookmarks ---
cmd_init_bookmarks() {
    local filter="${1:-}" targets
    targets=$(resolve_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🔗 Linking local main ↔ origin/main"
    for repo in $targets; do
        local name="$repo"
        gum spin --spinner dot --title "$name..." -- \
            bash -c "cd '$ROOT/$repo' && jj bookmark track main --remote=origin 2>&1 | grep -v 'already tracked' || true"
    done
    gum style --foreground 46 --margin "1 0" "✅ Bookmark tracking ensured."
}

# --- dispatch ---
subcommand="${1:-}"
[ -n "$subcommand" ] || { echo "Usage: jj-fleet <subcommand> [args...]" >&2; exit 1; }
shift
case "$subcommand" in
status-all) cmd_status_all "$@" ;;
remote-status) cmd_remote_status "$@" ;;
remote-prs) cmd_remote_prs "$@" ;;
remote-ci) cmd_remote_ci "$@" ;;
diff-all) cmd_diff_all "$@" ;;
check-signatures) cmd_check_signatures "$@" ;;
bootstrap) cmd_bootstrap "$@" ;;
init-bookmarks) cmd_init_bookmarks "$@" ;;
*)
    echo "Unknown subcommand: $subcommand" >&2
    echo "Available: status-all diff-all remote-status remote-prs remote-ci check-signatures bootstrap init-bookmarks" >&2
    exit 1
    ;;
esac
