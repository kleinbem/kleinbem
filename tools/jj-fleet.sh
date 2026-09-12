#!/usr/bin/env bash
# jj-fleet — Nix-packaged subset of the jj dashboard (kleinbem/flake.nix,
# writeShellApplication: pinned runtimeInputs + shellcheck-gated build).
#
# Covers the read-only/safe recipes only: status-all, diff-all,
# remote-status, remote-prs, remote-ci, check-signatures, bootstrap,
# init-bookmarks, sweep-merged. Everything with real mutation logic
# (save-all, push-all, ship-all, sign-unsigned, ...) is still in
# kleinbem/.just/jj.just, converted later once this phase proves out.
#
# No domain concept — one flat list of every repo in kleinbem/repos.nix, no
# nix/openwrt-specific handling anywhere. status-all with no filter shows
# everything, always, from anywhere in the workspace.
#
# Runnable from ANY directory under the workspace root, not just the three
# conductors — ROOT is found by walking up from $PWD looking for
# kleinbem/repos.nix (same trick git/jj use to find their own repo root).
# `just` recipes that already have {{ROOT}} pass it as an env var to skip the
# walk; direct invocation (typing `jj-fleet status-all` from inside any repo,
# once it's on PATH via the devshell) relies on the walk.
#
# Usage: jj-fleet <subcommand> [args...]
set -euo pipefail

find_root() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/kleinbem/repos.nix" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "jj-fleet: could not find the workspace root (no kleinbem/repos.nix found walking up from $PWD)" >&2
    return 1
}

ROOT="${ROOT:-$(find_root)}"

ALL_REPOS=$(nix eval --raw --file "$ROOT/kleinbem/repos.nix" \
    --apply 'rs: builtins.concatStringsSep " " (builtins.attrNames rs)' 2>/dev/null || true)

resolve_targets() {
    # shellcheck disable=SC2086 # intentional word-splitting of ALL_REPOS
    bash "$ROOT/kleinbem/tools/resolve-targets.sh" "$1" $ALL_REPOS
}

# --- status-all ---
cmd_status_all() {
    local filter="${1:-}" targets
    targets=$(resolve_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "📊 Workspace Status (jj)"
    # Per-repo @ state + ahead-of-trunk breakdown lives in
    # jj-toolbox/bin/jj-ahead — not duplicated here anymore. This loop fans
    # it out and re-decorates rows with a REPO column and this table's
    # emoji status style.
    {
        printf "REPO\tCHANGE\t@ STATE\tAHEAD OF ORIGIN\n"
        for repo in $targets; do
            local dir="$ROOT/$repo" name="$repo" change state ahead ready_part undesc_part
            [ -d "$dir" ] || continue
            IFS=$'\t' read -r change state ahead < <(cd "$dir" && "$ROOT/jj-toolbox/bin/jj-ahead" --tsv 2>/dev/null) || continue
            [ -z "$change" ] && continue
            case "$state" in
                "(empty)") : ;;
                UNDESCRIBED) state="⚠ undescribed" ;;
                *) state="📝 $state" ;;
            esac
            case "$ahead" in
                none) ahead="(none)" ;;
                *,*)
                    # "N ready, M undescribed" -> "📝N ⚠M (mixed)"
                    ready_part="${ahead%%,*}"
                    undesc_part="${ahead#*, }"
                    ahead="📝${ready_part%% *} ⚠${undesc_part%% *} (mixed)"
                    ;;
                *undescribed) ahead="⚠ $ahead" ;;
                *ready) ahead="📝 $ahead" ;;
            esac
            printf "%s\t%s\t%s\t%s\n" "$name" "$change" "$state" "$ahead"
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
    # Per-repo audit logic lives in jj-toolbox's jj-check-signatures (not
    # duplicated here anymore) — this loop just fans it out and folds its
    # output into one summary table. See jj-toolbox/bin/jj-check-signatures.
    local rows=("REPO	COMMITS	STATUS	DETAIL")
    for repo in $targets; do
        local name="$repo" dir="$ROOT/$repo" out status ahead detail
        out=$(cd "$dir" && "$ROOT/jj-toolbox/bin/jj-check-signatures" 2>&1) && status=0 || status=$?
        ahead=$(printf '%s\n' "$out" | tail -n +2 | grep -c '.' || true)
        if [ "$status" -ne 0 ]; then
            detail=$(printf '%s\n' "$out" | grep -m1 'UNSIGNED' || echo "—")
            rows+=("$(printf '%s\t%s\t%s\t%s' "$name" "$ahead" "❌ UNSIGNED" "$detail")")
            any_unsigned=1
        elif printf '%s\n' "$out" | grep -q 'unverified'; then
            rows+=("$(printf '%s\t%s\t%s\t%s' "$name" "$ahead" "⚠ unverified" "—")")
            any_unverified=1
        elif printf '%s\n' "$out" | grep -q 'nothing to check'; then
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
    targets=$(resolve_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🌱 Bootstrapping workspace from kleinbem/repos.nix"
    for repo in $targets; do
        local rpath="$ROOT/$repo"
        if [ -d "$rpath" ]; then
            gum style --foreground 46 "  ✓ $repo (already cloned)"
        else
            local url
            url=$(nix eval --raw --file "$ROOT/kleinbem/repos.nix" --apply "rs: rs.\"$repo\"")
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

# --- pull-all ---
cmd_pull_all() {
    local filter="${1:-}" targets
    targets=$(resolve_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "📥 Fetching + rebasing all repositories"
    # Per-repo fetch+rebase (with the credential-helper override that
    # dodges the oauth-device-flow hang) lives in jj-toolbox/bin/jj-pull —
    # not duplicated here anymore.
    for repo in $targets; do
        local name="$repo" rpath="$ROOT/$repo"
        gum spin --spinner dot --title "$name..." -- \
            bash -c "cd '$rpath' && '$ROOT/jj-toolbox/bin/jj-pull' >/dev/null 2>&1 || true"
    done
    gum style --foreground 46 --margin "1 0" "✅ pull-all complete. Run: just jj::status-all"
}

# --- save-all ---
cmd_save_all() {
    local msg="${1:-}" filter="${2:-}"
    if [ -z "$msg" ]; then
        msg=$(gum input --header "Commit message" --placeholder "feat(...): ...")
    fi
    if [ -z "$msg" ]; then
        gum style --foreground 196 "❌ No message provided. Aborting."
        exit 1
    fi
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "💾 Saving workspace state: $msg"
    local targets
    targets=$(resolve_targets "$filter")
    local author=""
    if [ -n "${KLEINBEM_PERSONA:-}" ]; then
        # full-name/email — only available via lib/personas.nix's joined
        # view (personas.nix alone never has them, by design).
        # kleinbem-secrets/personas/contact.nix is plain Nix (2026-08-09 —
        # full-name/email become public the moment a persona commits
        # anything, so sops-encrypting them at rest never bought real
        # confidentiality; import it directly, no decrypt step, no tmpfs
        # dance). This also drops the V2 NoTouch pipeline's former
        # dependency on nixos-nvme's TPM identity being a working sops
        # decrypt recipient for this specific file — one less thing that
        # could fail unattended.
        author=$(nix eval --raw --impure --expr "
            let
              lib = (import <nixpkgs> {}).lib;
              contact = import $ROOT/kleinbem-secrets/personas/contact.nix;
              p = import $ROOT/nix-config/lib/personas.nix { inherit lib contact; };
            in p.all.${KLEINBEM_PERSONA}.\"full-name\" + \" <\" + p.all.${KLEINBEM_PERSONA}.email + \">\"
        " 2>/dev/null)
        gum style --foreground 99 "🎭 Acting as: $author"
    fi
    # Classify dirty repos first: in a fan-out save, a repo whose ONLY change
    # is flake.lock churn gets a lockfile message instead of the unrelated
    # fan-out message. If EVERY dirty repo is lock-only, the given message is
    # kept — that's a deliberate lock bump.
    local dirty=() lockonly=() nonlock=0
    for repo in $targets; do
        local rpath="$ROOT/$repo" summary
        summary=$(cd "$rpath" 2>/dev/null && jj diff --summary 2>/dev/null) || summary=""
        if [ -n "$summary" ]; then
            dirty+=("$repo")
            if printf '%s\n' "$summary" | grep -qv 'flake\.lock$'; then
                nonlock=1
            else
                lockonly+=("$repo")
            fi
        fi
    done
    local any=0
    for repo in ${dirty[@]+"${dirty[@]}"}; do
        local name="$repo" rpath="$ROOT/$repo" rmsg="$msg"
        any=1
        if [ "$nonlock" -eq 1 ] && printf '%s\n' ${lockonly[@]+"${lockonly[@]}"} | grep -qxF -- "$repo"; then
            rmsg="chore: update flake lockfiles"
        fi
        gum style --foreground 212 "  📝 $name — describing ($rmsg)..."
        # Show exactly what's being committed — a fan-out save can otherwise
        # silently scoop another session's in-flight work.
        (cd "$rpath" && jj diff --summary 2>/dev/null | sed 's/^/     /')
        # Per-repo describe+advance+new lives in jj-toolbox/bin/jj-save —
        # not duplicated here anymore.
        local save_args=("$rmsg")
        [ -n "$author" ] && save_args=(--author "$author" "$rmsg")
        (cd "$rpath" && "$ROOT/jj-toolbox/bin/jj-save" "${save_args[@]}") >/dev/null 2>&1
    done
    if [ "$any" -eq 0 ]; then
        gum style --foreground 220 --margin "1 0" "✓ Workspace clean — nothing to describe."
    else
        gum style --foreground 46 --margin "1 0" "✅ Workspace state saved."
    fi
}

# --- save (single repo, fan-out-free) ---
cmd_save() {
    local repo="${1:?repo required}" msg="${2:?message required}"
    local dir="$ROOT/$repo"
    [ -d "$dir" ] || { gum style --foreground 196 "❌ No such repo dir: $repo"; exit 1; }
    local summary
    summary=$(cd "$dir" && jj diff --summary 2>/dev/null) || summary=""
    if [ -z "$summary" ]; then
        gum style --foreground 220 "✓ $repo clean — nothing to describe."
        exit 0
    fi
    printf '%s\n' "$summary" | sed 's/^/  /'
    (cd "$dir" && "$ROOT/jj-toolbox/bin/jj-save" "$msg") >/dev/null 2>&1
    gum style --foreground 46 "✅ $repo described: $msg"
}

# --- sign-unsigned ---
cmd_sign_unsigned() {
    local filter="${1:-}" targets
    targets=$(resolve_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🔐 Signing unsigned commits ahead of origin"
    # Per-repo signing logic (auto-advance, detached-HEAD handling, marker-
    # tagged stash dance, git rebase --exec re-sign) lives in
    # jj-toolbox/bin/jj-sign-unsigned — not duplicated here anymore.
    local any_done=0
    for repo in $targets; do
        local name="$repo" rpath="$ROOT/$repo" out status
        out=$(cd "$rpath" && "$ROOT/jj-toolbox/bin/jj-sign-unsigned" 2>&1) && status=0 || status=$?
        if printf '%s\n' "$out" | grep -q '^Nothing to sign'; then
            continue
        fi
        any_done=1
        if [ "$status" -eq 0 ]; then
            local header rest
            header=$(printf '%s\n' "$out" | head -1)
            rest=$(printf '%s\n' "$out" | tail -n +2)
            gum style --foreground 212 "  🖊  $name — ${header,,}"
            [ -n "$rest" ] && printf '%s\n' "$rest" | sed 's/^/    ↳ /'
        else
            gum style --foreground 196 "  ⚠ rebase failed in $name — fix manually"
            printf '%s\n' "$out" | sed 's/^/    /'
        fi
    done
    if [ "$any_done" -eq 0 ]; then
        gum style --foreground 46 --margin "1 0" "✓ Nothing to sign — all ahead-of-origin commits already signed"
    else
        gum style --foreground 46 --margin "1 0" "✅ Done. Verify with: just jj::check-signatures"
    fi
}

# --- push-all ---
cmd_push_all() {
    local filter="${1:-}" targets
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "📤 Pushing all changes (verified on origin)"
    targets=$(resolve_targets "$filter")
    local failed=()
    for repo in $targets; do
        local name="$repo" rpath="$ROOT/$repo" url="https://github.com/kleinbem/$repo.git"
        (
        cd "$rpath" 2>/dev/null || { gum style --foreground 196 "  ❌ $name (dir missing)"; exit 1; }
        target=$(jj log -r main --no-graph -T 'commit_id' 2>/dev/null)
        [ -z "$target" ] && { gum style --foreground 244 "  ⏭  $name (no main bookmark)"; exit 0; }
        before=$(git -c credential.helper= -c credential.helper='!gh auth git-credential' ls-remote "$url" refs/heads/main 2>/dev/null | cut -f1)
        # A described commit past main hasn't been advanced onto the
        # bookmark yet (jj-push does that itself) — only skip when there's
        # truly nothing to advance AND remote already matches.
        pending=$(jj log -r 'main..@' --no-graph -T 'description' 2>/dev/null)
        [ "$before" = "$target" ] && [ -z "$pending" ] && { gum style --foreground 244 "  ✓ $name up to date (${target:0:12})"; exit 0; }
        # Per-repo push mechanics (bookmark-advance, push, credential-helper
        # override, fetch+rebase+retry once on divergence) live in
        # jj-toolbox/bin/jj-push — not duplicated here anymore. This loop
        # just fans it out and verifies the result against origin.
        out=$("$ROOT/jj-toolbox/bin/jj-push" 2>&1 || true)
        target=$(jj log -r main --no-graph -T 'commit_id' 2>/dev/null)
        after=$(git -c credential.helper= -c credential.helper='!gh auth git-credential' ls-remote "$url" refs/heads/main 2>/dev/null | cut -f1)
        if [ "$after" = "$target" ] && [ -n "$target" ]; then
            git update-ref refs/remotes/origin/main "$target" 2>/dev/null || true
            jj git import >/dev/null 2>&1 || true
            gum style --foreground 46 "  ✅ $name → ${target:0:12} (verified on origin)"
        else
            gum style --foreground 196 "  ❌ $name — remote still ${after:0:12}, NOT pushed"
            printf '%s\n' "$out" | grep -iE 'rejected|error|denied|signature|fetch first|behind|protected' | sed 's/^/     /' | head -3
            exit 1
        fi
        ) || failed+=("$name")
    done
    if [ ${#failed[@]} -gt 0 ]; then
        gum style --foreground 196 --margin "1 0" "❌ NOT pushed: ${failed[*]}"
        gum style --foreground 220 "   ↳ diverged remote → 'just jj::pull-all' then retry  ·  unsigned → 'just jj::sign-unsigned'  ·  scope → 'gh auth refresh -s workflow'"
        exit 1
    else
        gum style --foreground 46 --margin "1 0" "✅ All pushes verified on origin."
    fi
}

# --- sync (bootstrap + pull-all) ---
cmd_sync() {
    local filter="${1:-}"
    cmd_bootstrap "$filter"
    cmd_pull_all "$filter"
}

# --- sweep-merged ---
# Read-only diagnostic — fetches+prunes every repo in scope, then reports
# every local branch other than main and whether its content already made
# it into origin/main. Three detection methods, weakest-signal last:
#   1. ancestor-of-origin/main   — plain/fast-forward merges
#   2. commit-subject match      — squash-merges (GitHub's default squash
#      message is "<original subject> (#N)", so the branch tip's own
#      subject line shows up verbatim inside a main commit's subject)
#   3. gh PR search by head ref  — catches anything method 2 misses (e.g.
#      an amended commit message), at the cost of one gh API call/branch
# Also flags `gh pr checkout <N>` residue (refs/remotes/pr/* — gh's local
# tracking convention, not a real GitHub branch) since that's always dead
# weight regardless of merge status.
# Never deletes anything itself — a heuristic false-positive across a whole
# fleet run unattended is worse than one extra manual step. Prints the
# `jj bookmark forget` command for whatever it flags; run that by hand (or
# ask an agent) once you've eyeballed the table.
cmd_sweep_merged() {
    local filter="${1:-}" targets
    targets=$(resolve_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🧹 Branch sweep — local branches vs. origin/main"
    # Per-repo detection (ancestor/squash-subject/gh-PR-search, plus gh-pr-
    # checkout residue) lives in jj-toolbox/bin/jj-sweep-merged — not
    # duplicated here anymore. This loop fans it out and re-decorates rows
    # with a REPO column and this table's emoji status style.
    local rows=("REPO	BRANCH	STATUS	DETAIL") any=0
    for repo in $targets; do
        local dir="$ROOT/$repo" name="$repo" out
        [ -d "$dir" ] || continue
        out=$(cd "$dir" && "$ROOT/jj-toolbox/bin/jj-sweep-merged" --tsv 2>/dev/null) || continue
        [ -z "$out" ] && continue
        any=1
        while IFS=$'\t' read -r branch status detail; do
            [ -z "$branch" ] && continue
            case "$status" in
                MERGED) status="✅ MERGED" ;;
                RESIDUE) status="🗑 RESIDUE" ;;
                *) status="⚠ $status" ;;
            esac
            rows+=("$(printf '%s\t%s\t%s\t%s' "$name" "$branch" "$status" "$detail")")
        done <<<"$out"
    done
    if [ "$any" -eq 0 ]; then
        gum style --foreground 46 --margin "1 0" "✅ Every repo in scope is main-only. Nothing to sweep."
        return
    fi
    printf '%s\n' "${rows[@]}" | gum table -s "$(printf '\t')" --print
    gum style --foreground 220 --margin "1 0" "ℹ Read-only — nothing deleted. To clean up a flagged branch:"
    gum style --foreground 244 "   jj bookmark forget <branch>                 # local cleanup"
    gum style --foreground 244 "   jj git push --deleted                      # only if it was ever pushed to origin"
    gum style --foreground 244 "   git branch -r -D pr/<N> && jj git import   # for gh-pr-checkout residue"
}

# --- branch-all ---
cmd_branch_all() {
    # Named bookmark_name, not "name" — the per-repo loop below already uses
    # $name as its own local (matching the pattern of every other subcommand
    # here), and unlike the old just recipe (where {{name}} was a literal
    # text-substitution done before bash ever ran, so it couldn't collide
    # with a same-named bash variable), these are now real bash locals that
    # would otherwise shadow each other.
    local bookmark_name="${1:?bookmark name required}" filter="${2:-}"
    gum confirm "🌿 Create bookmark '$bookmark_name' across the workspace?" || exit 0
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🌿 Creating bookmark '$bookmark_name'"
    local targets
    targets=$(resolve_targets "$filter")
    for repo in $targets; do
        local name="$repo"
        gum spin --spinner dot --title "$name..." -- \
            bash -c "cd '$ROOT/$repo' && jj bookmark create '$bookmark_name'"
    done
    gum style --foreground 46 --margin "1 0" "✅ Bookmark created."
}

# --- workspace-new / workspace-list / workspace-gc ---
#
# jj workspaces give each concurrent agent/session its own working-copy
# commit and its own files on disk, sharing only the commit graph and op
# log with the repo's primary checkout. That fixes the failure mode where
# one Claude tab's `jj new`/`abandon`/`undo`/`restore` silently discards or
# moves another tab's in-progress edits, because they were all sharing one
# @ in the primary checkout.
#
# Added workspaces live at <repo>.ws/<name>/, a sibling of the repo dir —
# outside repos.nix's flat namespace, so no *-all fan-out recipe ever
# touches them. They are jj-only (no .git): raw git doesn't work there,
# only jj. `jj git push`/pull-all/push-all still work from any workspace
# since the git backend is shared with the primary checkout.
cmd_workspace_new() {
    local repo="${1:?repo required}" name="${2:-}"
    local dir="$ROOT/$repo"
    [ -d "$dir" ] || { gum style --foreground 196 "❌ No such repo dir: $repo"; exit 1; }
    # Resolve the name here (rather than letting jj-ws-new auto-generate
    # one) so this can print the exact path without parsing its output.
    [ -z "$name" ] && name="ws-$(date +%H%M%S)-$RANDOM"
    local ws_path="${dir}.ws/$name"
    # Workspace creation (mkdir, jj workspace add -r trunk(), .envrc copy)
    # lives in jj-toolbox/bin/jj-ws-new — not duplicated here anymore.
    if (cd "$dir" && "$ROOT/jj-toolbox/bin/jj-ws-new" "$name") >/dev/null 2>&1; then
        gum style --foreground 46 --margin "1 0" "✅ Workspace '$name' ready — cd here and work:"
        gum style --foreground 212 "   cd $ws_path"
    else
        gum style --foreground 196 "❌ jj workspace add failed — is trunk tracked here? Try: just jj::init-bookmarks $repo"
        exit 1
    fi
}

cmd_workspace_list() {
    local filter="${1:-}" targets any=0
    targets=$(resolve_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🗂  Agent workspaces"
    # Per-workspace state detection (empty/dirty-undescribed/described, via
    # a fresh cd-in snapshot) lives in jj-toolbox/bin/jj-ws-list — not
    # duplicated here anymore.
    local rows=("REPO	WORKSPACE	@ STATE	DIR")
    for repo in $targets; do
        local dir="$ROOT/$repo" out
        [ -d "$dir" ] || continue
        out=$(cd "$dir" && "$ROOT/jj-toolbox/bin/jj-ws-list" --tsv 2>/dev/null) || continue
        [ -z "$out" ] && continue
        any=1
        while IFS=$'\t' read -r wname state wroot; do
            [ -z "$wname" ] && continue
            rows+=("$(printf '%s\t%s\t%.40s\t%s' "$repo" "$wname" "$state" "$wroot")")
        done <<<"$out"
    done
    if [ "$any" -eq 0 ]; then
        gum style --foreground 46 --margin "1 0" "✓ No agent workspaces open."
    else
        printf '%s\n' "${rows[@]}" | gum table -s "$(printf '\t')" --print
    fi
}

cmd_workspace_gc() {
    local filter="" hours=4
    while [ $# -gt 0 ]; do
        case "$1" in
        --hours) hours="${2:?}"; shift 2 ;;
        *) filter="$1"; shift ;;
        esac
    done
    local targets
    targets=$(resolve_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🧹 Agent workspace GC (age ≥ ${hours}h, empty+undescribed only)"
    # Per-workspace reap decision (fresh cd-in snapshot, empty+undescribed+
    # aged-out or orphaned dir) lives in jj-toolbox/bin/jj-ws-gc — not
    # duplicated here anymore. This loop fans it out and sums the totals.
    local reaped=0 kept=0
    for repo in $targets; do
        local dir="$ROOT/$repo" out
        [ -d "$dir" ] || continue
        out=$(cd "$dir" && "$ROOT/jj-toolbox/bin/jj-ws-gc" --hours "$hours" 2>&1) || true
        [ -z "$out" ] && continue
        while IFS= read -r line; do
            case "$line" in
                reaped\ *)
                    gum style --foreground 46 "  ✓ reaped $repo/${line#reaped }"
                    ;;
                "GC done:"*)
                    local r k
                    r=$(printf '%s' "$line" | grep -oE '^GC done: [0-9]+' | grep -oE '[0-9]+')
                    k=$(printf '%s' "$line" | grep -oE '[0-9]+ kept' | grep -oE '[0-9]+')
                    reaped=$((reaped + r))
                    kept=$((kept + k))
                    ;;
            esac
        done <<<"$out"
    done
    gum style --foreground 46 --margin "1 0" "✅ GC done: $reaped reaped, $kept kept (has content, described, or too new)."
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
pull-all) cmd_pull_all "$@" ;;
save-all) cmd_save_all "$@" ;;
save) cmd_save "$@" ;;
sign-unsigned) cmd_sign_unsigned "$@" ;;
push-all) cmd_push_all "$@" ;;
sync) cmd_sync "$@" ;;
branch-all) cmd_branch_all "$@" ;;
sweep-merged) cmd_sweep_merged "$@" ;;
workspace-new) cmd_workspace_new "$@" ;;
workspace-list) cmd_workspace_list "$@" ;;
workspace-gc) cmd_workspace_gc "$@" ;;
*)
    echo "Unknown subcommand: $subcommand" >&2
    echo "Available: status-all diff-all remote-status remote-prs remote-ci check-signatures bootstrap init-bookmarks pull-all save-all save sign-unsigned push-all sync branch-all sweep-merged workspace-new workspace-list workspace-gc" >&2
    exit 1
    ;;
esac
