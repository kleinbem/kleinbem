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
    for repo in $targets; do
        local name="$repo" rpath="$ROOT/$repo" url="https://github.com/kleinbem/$repo.git"
        gum spin --spinner dot --title "$name..." -- \
            bash -c "cd '$rpath' && git -c credential.helper= -c credential.helper='!gh auth git-credential' fetch '$url' main:refs/remotes/origin/main >/dev/null 2>&1 && jj git import >/dev/null 2>&1 && jj rebase -d main@origin >/dev/null 2>&1 || true"
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
        # email/full-name are PII — only available via lib/personas.nix's
        # joined view (personas.nix alone never has them, by design).
        author=$(nix eval --raw --impure --expr "
            let
              lib = (import <nixpkgs> {}).lib;
              contactPath = $ROOT/nix-secrets/personas-contact.nix;
              contact = if builtins.pathExists contactPath then import contactPath else {};
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
        if [ -n "$author" ]; then
            (cd "$rpath" && jj describe -m "$rmsg" --author "$author" && jj bookmark move main --to @ && jj new) >/dev/null 2>&1
        else
            (cd "$rpath" && jj describe -m "$rmsg" && jj bookmark move main --to @ && jj new) >/dev/null 2>&1
        fi
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
    (cd "$dir" && jj describe -m "$msg" && jj bookmark move main --to @ && jj new) >/dev/null 2>&1
    gum style --foreground 46 "✅ $repo described: $msg"
}

# --- sign-unsigned ---
cmd_sign_unsigned() {
    local filter="${1:-}" targets
    targets=$(resolve_targets "$filter")
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🔐 Signing unsigned commits ahead of origin"
    local any_done=0
    for repo in $targets; do
        local name="$repo" rpath="$ROOT/$repo"
        # Auto-advance: if @ has a description and is ahead of main bookmark,
        # move main to @ so the unsigned commit becomes visible to git.
        if [ -n "$(cd "$rpath" && jj log -r 'main..@' --no-graph -T 'description' 2>/dev/null)" ]; then
            (cd "$rpath" && jj bookmark move main --to @ >/dev/null 2>&1 || true)
        fi
        local unsigned
        # Repos with no origin/main yet (e.g. never pushed) make `git log`
        # fail fatally — harmless under the original per-recipe `set -e`
        # (no pipefail there), but this script's global `set -euo pipefail`
        # would otherwise abort the whole run. Check the ref exists first
        # rather than trying to recover after the fact — wc -l happily
        # reports "0" even when the upstream git command failed, so a bare
        # "|| echo 0" fallback here would double up the output instead of
        # replacing it.
        if git -C "$rpath" rev-parse -q --verify origin/main >/dev/null 2>&1; then
            unsigned=$(git -C "$rpath" log --format='%G?' "origin/main..main" 2>/dev/null \
                | awk '$1 != "G" && $1 != ""' | wc -l)
        else
            unsigned=0
        fi
        if [ "$unsigned" -gt 0 ]; then
            gum style --foreground 212 "  🖊  $name — re-signing $unsigned commit(s)..."
            # Pre-flight: jj-colocated repos frequently leave git's HEAD
            # detached. `git rebase` needs an attached branch. Detect
            # detached HEAD and force-attach to main BEFORE the stash dance —
            # safe because after the auto-advance above, jj's working copy
            # == main == tree, so `checkout -f main` doesn't discard anything.
            local head_ref
            head_ref=$(cd "$rpath" && git symbolic-ref --quiet HEAD 2>/dev/null || true)
            if [ "$head_ref" != "refs/heads/main" ]; then
                (cd "$rpath" && git checkout -f main >/dev/null 2>&1 || true)
            fi
            # Stash dance — unique marker so we never accidentally pop a
            # pre-existing stash from earlier work.
            local stash_msg
            stash_msg="auto-stash-sign-unsigned-$$-$(date +%s%N)"
            (cd "$rpath" && git stash push -u -m "$stash_msg" >/dev/null 2>&1 || true)
            local stash_ref
            stash_ref=$(cd "$rpath" && git stash list 2>/dev/null | grep -F "$stash_msg" | head -1 | cut -d: -f1)
            (cd "$rpath" && git checkout main >/dev/null 2>&1 || true)
            # shellcheck disable=SC2016 # single-quoted on purpose: this is a
            # shell fragment for git-rebase's spawned shell to expand, not us
            if (cd "$rpath" && git rebase --exec \
                'if [ "$(git log -1 --format=%G?)" != "G" ]; then git commit --amend --no-edit -S; fi' \
                origin/main); then
                if [ "$(git -C "$rpath" symbolic-ref --quiet HEAD 2>/dev/null)" = "refs/heads/main" ]; then
                    (cd "$rpath" && jj git import >/dev/null 2>&1) \
                        && gum style --foreground 46 "    ↳ main at signed HEAD; jj bookmark synced"
                else
                    (cd "$rpath" && git branch -f main HEAD && git checkout main >/dev/null 2>&1 && jj git import >/dev/null 2>&1) \
                        && gum style --foreground 46 "    ↳ reattached main + jj bookmark"
                fi
                # Pop ONLY our marker-tagged stash, never a pre-existing one.
                [ -n "$stash_ref" ] && (cd "$rpath" && git stash pop "$stash_ref" >/dev/null 2>&1 || true)
            else
                [ -n "$stash_ref" ] && (cd "$rpath" && git stash pop "$stash_ref" >/dev/null 2>&1 || true)
                gum style --foreground 196 "    ⚠ rebase failed in $name — fix manually"
            fi
            any_done=1
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
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "📤 Pushing all changes (HTTPS+gh, verified)"
    targets=$(resolve_targets "$filter")
    local failed=()
    for repo in $targets; do
        local name="$repo" rpath="$ROOT/$repo" url="https://github.com/kleinbem/$repo.git"
        (
        cd "$rpath" 2>/dev/null || { gum style --foreground 196 "  ❌ $name (dir missing)"; exit 1; }
        # Advance main to @ if there are new described commits.
        if [ -n "$(jj log -r 'main..@' --no-graph -T 'description' 2>/dev/null)" ]; then
            jj bookmark move main --to @ >/dev/null 2>&1 || true
        fi
        target=$(jj log -r main --no-graph -T 'commit_id' 2>/dev/null)
        [ -z "$target" ] && { gum style --foreground 244 "  ⏭  $name (no main bookmark)"; exit 0; }
        before=$(git -c credential.helper= -c credential.helper='!gh auth git-credential' ls-remote "$url" refs/heads/main 2>/dev/null | cut -f1)
        [ "$before" = "$target" ] && { gum style --foreground 244 "  ✓ $name up to date (${target:0:12})"; exit 0; }
        attempt=1
        while :; do
            out=$(git -c credential.helper= -c credential.helper='!gh auth git-credential' push "$url" "$target:refs/heads/main" 2>&1 || true)
            after=$(git -c credential.helper= -c credential.helper='!gh auth git-credential' ls-remote "$url" refs/heads/main 2>/dev/null | cut -f1)
            [ "$after" = "$target" ] && break
            # Diverged remote: recover in place — fetch, import, rebase our
            # work onto origin, re-advance main — retry the push ONCE.
            if [ "$attempt" -eq 1 ] && printf '%s\n' "$out" | grep -qiE 'fetch first|non-fast-forward|behind'; then
                attempt=2
                gum style --foreground 220 "  🔁 $name diverged — fetch + rebase, retrying once..."
                git -c credential.helper= -c credential.helper='!gh auth git-credential' fetch "$url" main:refs/remotes/origin/main >/dev/null 2>&1 || true
                jj git import >/dev/null 2>&1 || true
                jj rebase -d main@origin >/dev/null 2>&1 || true
                if [ -n "$(jj log -r 'main..@' --no-graph -T 'description' 2>/dev/null)" ]; then
                    jj bookmark move main --to @ >/dev/null 2>&1 || true
                fi
                target=$(jj log -r main --no-graph -T 'commit_id' 2>/dev/null)
                continue
            fi
            break
        done
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
*)
    echo "Unknown subcommand: $subcommand" >&2
    echo "Available: status-all diff-all remote-status remote-prs remote-ci check-signatures bootstrap init-bookmarks pull-all save-all save sign-unsigned push-all sync branch-all" >&2
    exit 1
    ;;
esac
