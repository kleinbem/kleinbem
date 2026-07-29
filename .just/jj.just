import 'common.just'

set working-directory := "."
export JJ_PAGER := "cat"

# --- Workspace VCS operations (jj-first) ---
#
# Canonical copy — nix/.just/jj.just and openwrt/.just/jj.just are symlinks
# to this file. Every recipe operates on {{REPOS}} (this conductor's default
# scope: itself + its domain's sub-repos + anything tagged "shared") unless
# a `filter` argument is given, in which case it substring-matches against
# the WHOLE fleet ({{ALL_REPOS}}) — so `just jj::status-all nix-secrets`
# works from openwrt/ too. See kleinbem/tools/resolve-targets.sh.
#
# Each repo listed in `kleinbem/repos.nix` is its own independent git+jj repo
# (NOT a git submodule — see `just jj::bootstrap`). The three conductors
# (nix/, openwrt/, kleinbem/) are colocated jj repos too, and are addressable
# by name like any other repo.
#
# Use `git` only for legacy rescue ops or destructive resets — none of
# those are wrapped here; type them directly when needed.
#
# TUI output uses `gum` (charmbracelet/gum) — install via `nix-env` or
# add to home-manager packages. Recipes degrade noticeably if absent
# (they call gum and the user sees "gum: command not found").
#
# --- Signing ---
#
# Today's reality: commits are signed via `git commit --amend -S` during
# `sign-unsigned`, which touches the YubiKey on every signing operation.
# TODO: wire a NoTouch SSH-FIDO key + `sign-all = true` in ~/.config/jj/
# config.toml so jj signs at describe-time without prompting. Until then,
# expect one YubiKey touch per repo per signing pass.

# Resolve the repos this invocation should operate on: `filter` narrows
# fleet-wide by substring when given, else the caller's default scope.
_targets := "bash " + ROOT + "/kleinbem/tools/resolve-targets.sh"

# --- Interactive hub ---

# Interactive launcher — fuzzy-pick a workspace operation. Great for
# muscle memory: just type `j` (or whatever alias) → pick.
[group("Status")]
hub:
    #!/usr/bin/env bash
    set -e
    choice=$(gum choose --header "📦 Workspace Operations ({{file_name(justfile_directory())}})" \
        "ship-all         — describe + sign + push (the everything button)" \
        "─────────────────────────────────────────────" \
        "status-all       — repo state + ahead-of-origin counts" \
        "diff-all         — uncommitted changes across the workspace" \
        "remote-status    — GitHub dashboard (CI, PRs, issues)" \
        "remote-prs       — open PRs across the workspace" \
        "remote-ci        — recent CI runs per repo" \
        "check-signatures — audit signatures on commits ahead of origin" \
        "─────────────────────────────────────────────" \
        "pull-all         — fetch + rebase every sub-repo" \
        "save-all         — describe (commit) all dirty repos" \
        "sign-unsigned    — sign unsigned commits ahead of origin" \
        "push-all         — push every repo" \
        "─────────────────────────────────────────────" \
        "sync             — bootstrap + pull-all" \
        "init-bookmarks   — link local main to origin/main" \
        "quit")
    case "$choice" in
        ship-all*)          msg=$(gum input --header "Ship message" --placeholder "feat(...): ..."); just jj::ship-all "$msg" ;;
        status-all*)        just jj::status-all ;;
        diff-all*)          just jj::diff-all ;;
        remote-status*)     just jj::remote-status ;;
        remote-prs*)        just jj::remote-prs ;;
        remote-ci*)         just jj::remote-ci ;;
        check-signatures*)  just jj::check-signatures ;;
        pull-all*)          just jj::pull-all ;;
        save-all*)          msg=$(gum input --placeholder "Commit message"); just jj::save-all "$msg" ;;
        sign-unsigned*)     just jj::sign-unsigned ;;
        push-all*)          just jj::push-all ;;
        sync*)              just jj::sync ;;
        init-bookmarks*)    just jj::init-bookmarks ;;
        *) exit 0 ;;
    esac

# --- Status / read-only ---

# Compact workspace overview — change_id, @ state (described or not),
# and a count of described vs undescribed commits ahead of origin/main.
#   just jj::status-all              # this conductor's default scope
#   just jj::status-all nix          # everything matching "nix" fleet-wide
#   just jj::status-all nix-secrets  # just that one repo, from anywhere
[group("Status")]
status-all filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh status-all {{filter}}

# GitHub remote dashboard — origin/main SHA, latest CI status,
# open PR count, open issue count per repo. ~6s due to gh API roundtrips.
[group("Status")]
remote-status filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh remote-status {{filter}}

# Every open PR across the scope as a flat table.
[group("Status")]
remote-prs filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh remote-prs {{filter}}

# Recent CI workflow runs per repo as a single flat table.
[group("Status")]
remote-ci limit="5" filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh remote-ci {{limit}} {{filter}}

# Show the working-copy diff for every dirty repo in scope.
# Variadic — pass any `jj diff` flag through:
#   just jj::diff-all             # default jj diff, this conductor's scope
#   just jj::diff-all -- --git    # git-style
#   just jj::diff-all nix --stat  # filtered to "nix", stat summary
[group("Status")]
diff-all filter="" *args="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh diff-all {{filter}} {{args}}

# Audit commits ahead of origin for missing signatures.
# Status codes (git's %G?):
#   G  good signature, verified locally
#   U  signed but signing key not in ~/.ssh/allowed_signers
#   B  bad signature (forgery/corruption)
#   N  NO signature — the real problem; GitHub will reject
#   E, X, Y, R  various error states
[group("Status")]
check-signatures filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh check-signatures {{filter}}

# Sign every unsigned commit ahead of origin, in scope.
# Uses `git rebase --exec` rather than `jj sign` (more reliable).
# Auto-advances the local `main` bookmark to @ first if @ has a description
# and is ahead — so users can run `sign-unsigned` directly after `jj describe`
# without needing a redundant `push-all` to trigger the bookmark move.
# First operation per session may need a YubiKey PIN; cached thereafter.
[group("Sync")]
sign-unsigned filter="":
    #!/usr/bin/env bash
    set -e
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🔐 Signing unsigned commits ahead of origin"
    targets=$({{_targets}} "{{filter}}" {{REPOS}} -- {{ALL_REPOS}})
    any_done=0
    for repo in $targets; do
        name="$repo"
        rpath="{{ROOT}}/$repo"
        # Auto-advance: if @ has a description and is ahead of main bookmark,
        # move main to @ so the unsigned commit becomes visible to git.
        if [ -n "$(cd "$rpath" && jj log -r 'main..@' --no-graph -T 'description' 2>/dev/null)" ]; then
            (cd "$rpath" && jj bookmark move main --to @ >/dev/null 2>&1 || true)
        fi
        unsigned=$(git -C "$rpath" log --format='%G?' "origin/main..main" 2>/dev/null \
            | awk '$1 != "G" && $1 != ""' | wc -l)
        if [ "$unsigned" -gt 0 ]; then
            gum style --foreground 212 "  🖊  $name — re-signing $unsigned commit(s)..."
            # Pre-flight: jj-colocated repos frequently leave git's HEAD
            # detached (from various jj ops, prior rebase failures, etc.).
            # `git rebase` needs an attached branch. Detect detached HEAD and
            # force-attach to main BEFORE the stash dance. Safe because after
            # the auto-advance above, jj's working copy == main == tree, so
            # `checkout -f main` doesn't discard anything new.
            head_ref=$(cd "$rpath" && git symbolic-ref --quiet HEAD 2>/dev/null || true)
            if [ "$head_ref" != "refs/heads/main" ]; then
                (cd "$rpath" && git checkout -f main >/dev/null 2>&1 || true)
            fi
            # Stash dance — use a unique marker so we never accidentally pop a
            # pre-existing stash that lives in the user's stash list from
            # earlier work. `git stash push` on a clean tree exits 0 without
            # actually creating an entry, so we verify the entry by message.
            stash_msg="auto-stash-sign-unsigned-$$-$(date +%s%N)"
            (cd "$rpath" && git stash push -u -m "$stash_msg" >/dev/null 2>&1 || true)
            stash_ref=$(cd "$rpath" && git stash list 2>/dev/null | grep -F "$stash_msg" | head -1 | cut -d: -f1)
            (cd "$rpath" && git checkout main >/dev/null 2>&1 || true)
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

# --- Sync ---

# Fetch from origin in every repo in scope and rebase the working-copy change.
[group("Sync")]
pull-all filter="":
    #!/usr/bin/env bash
    set -e
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "📥 Fetching + rebasing all repositories"
    targets=$({{_targets}} "{{filter}}" {{REPOS}} -- {{ALL_REPOS}})
    for repo in $targets; do
        name="$repo"
        rpath="{{ROOT}}/$repo"
        url="https://github.com/kleinbem/${name}.git"
        gum spin --spinner dot --title "$name..." -- \
            bash -c "cd '$rpath' && git -c credential.helper= -c credential.helper='!gh auth git-credential' fetch '$url' main:refs/remotes/origin/main >/dev/null 2>&1 && jj git import >/dev/null 2>&1 && jj rebase -d main@origin >/dev/null 2>&1 || true"
    done
    gum style --foreground 46 --margin "1 0" "✅ pull-all complete. Run: just jj::status-all"

# Describe (commit) dirty changes across the scope.
# Prompts for message via gum input if not given.
#   just jj::save-all "feat: stalwart container"
#   just jj::save-all                       # prompts
#   just jj::save-all "fix: qos" openwrt     # filtered to "openwrt"
[group("Sync")]
save-all message="" filter="":
    #!/usr/bin/env bash
    set -e
    msg="{{message}}"
    if [ -z "$msg" ]; then
        msg=$(gum input --header "Commit message" --placeholder "feat(...): ...")
    fi
    if [ -z "$msg" ]; then
        gum style --foreground 196 "❌ No message provided. Aborting."
        exit 1
    fi
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "💾 Saving workspace state: $msg"
    targets=$({{_targets}} "{{filter}}" {{REPOS}} -- {{ALL_REPOS}})
    author=""
    if [ -n "${KLEINBEM_PERSONA:-}" ]; then
        author=$(nix eval --raw --file {{ROOT}}/nix-config/personas.nix --apply \
            "p: p.${KLEINBEM_PERSONA}.full-name + \" <\" + p.${KLEINBEM_PERSONA}.email + \">\"" 2>/dev/null)
        gum style --foreground 99 "🎭 Acting as: $author"
    fi
    # Classify dirty repos first: in a fan-out save, a repo whose ONLY change
    # is flake.lock churn gets a lockfile message instead of the unrelated
    # fan-out message (prevents "repair cert for monitoring" landing on pure
    # lock bumps). If EVERY dirty repo is lock-only, the given message is
    # kept — that's a deliberate lock bump.
    dirty=()
    lockonly=()
    nonlock=0
    for repo in $targets; do
        rpath="{{ROOT}}/$repo"
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
    any=0
    for repo in ${dirty[@]+"${dirty[@]}"}; do
        name="$repo"
        rpath="{{ROOT}}/$repo"
        any=1
        rmsg="$msg"
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

# Describe (commit) ONE repo only — the fan-out-free path for when other
# repos carry someone else's in-flight work (parallel agent session, open
# editor). Works with any repo name in the fleet, including "nix"/"openwrt"/
# "kleinbem" themselves.
#   just jj::save nix-packages "fix(langfuse): bump fetcher"
[group("Sync")]
save repo message:
    #!/usr/bin/env bash
    set -e
    repo="{{repo}}"
    msg="{{message}}"
    dir="{{ROOT}}/$repo"
    [ -d "$dir" ] || { gum style --foreground 196 "❌ No such repo dir: $repo"; exit 1; }
    summary=$(cd "$dir" && jj diff --summary 2>/dev/null) || summary=""
    if [ -z "$summary" ]; then
        gum style --foreground 220 "✓ $repo clean — nothing to describe."
        exit 0
    fi
    printf '%s\n' "$summary" | sed 's/^/  /'
    (cd "$dir" && jj describe -m "$msg" && jj bookmark move main --to @ && jj new) >/dev/null 2>&1
    gum style --foreground 46 "✅ $repo described: $msg"

# One-shot: describe every dirty repo in scope with the given message, sign
# anything unsigned ahead of origin, and push. The "commit and ship"
# muscle-memory command — covers the entire describe → sign → push flow in
# one keystroke. `ship` is kept as an alias for muscle memory.
#
# With V2 NoTouch signing active this whole pipeline is silent and ~5s.
# If a sub-repo's signed-commit branch rule rejects, push-all surfaces it.
#
# Prompts for the message via `gum input` if not given. Same persona env
# var (KLEINBEM_PERSONA) works as with save-all.
[group("Sync")]
ship-all message="" filter="":
    #!/usr/bin/env bash
    set -e
    msg="{{message}}"
    if [ -z "$msg" ]; then
        msg=$(gum input --header "Ship: commit message" --placeholder "feat(...): ...")
    fi
    if [ -z "$msg" ]; then
        gum style --foreground 196 "❌ No message — aborting ship."
        exit 1
    fi
    gum style --border normal --padding "0 2" --border-foreground 99 --foreground 99 "🚢 Shipping: $msg"
    just jj::save-all "$msg" "{{filter}}"
    # Flake-lockfile sync only makes sense where a maintenance::update-local
    # recipe actually exists (nix/ has one; openwrt/kleinbem don't, no flakes
    # to sync). Check for the recipe directly rather than hardcoding a repo
    # name — works the same way for any future repo, flake or not.
    if just --show maintenance::update-local >/dev/null 2>&1; then
        just maintenance::update-local
        just jj::save-all "chore: update flake lockfiles" "{{filter}}"
    fi
    just jj::sign-unsigned "{{filter}}"
    just jj::push-all "{{filter}}"
    gum style --foreground 46 --margin "1 0" "✅ Shipped."

alias ship := ship-all

# Push every repo in scope. Auto-advances main bookmark to @ if @ has a
# description and is ahead of local main. Covers the common
# describe-then-push flow.
[group("Sync")]
push-all filter="":
    #!/usr/bin/env bash
    set -uo pipefail
    # Pushes over HTTPS using gh's token (the SSH/FIDO2 path silently fails inside
    # a spinner — the touch/agent prompt can't show), and VERIFIES the remote SHA
    # actually advanced before claiming success. Never trust jj's "Move forward"
    # line: that's the *planned* push, printed before auth runs. Requires the gh
    # token to carry the `workflow` scope (gh auth refresh -s workflow) so it can
    # push .github/workflows changes.
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "📤 Pushing all changes (HTTPS+gh, verified)"
    targets=$({{_targets}} "{{filter}}" {{REPOS}} -- {{ALL_REPOS}})
    failed=()
    for repo in $targets; do
        name="$repo"
        rpath="{{ROOT}}/$repo"
        url="https://github.com/kleinbem/${name}.git"
        (
        cd "$rpath" 2>/dev/null || { gum style --foreground 196 "  ❌ $name (dir missing)"; exit 1; }
        # Advance main to @ if there are new described commits (describe-then-push flow).
        if [ -n "$(jj log -r 'main..@' --no-graph -T 'description' 2>/dev/null)" ]; then
            jj bookmark move main --to @ >/dev/null 2>&1 || true
        fi
        target=$(jj log -r main --no-graph -T 'commit_id' 2>/dev/null)
        [ -z "$target" ] && { gum style --foreground 244 "  ⏭  $name (no main bookmark)"; exit 0; }
        before=$(git -c credential.helper= -c credential.helper='!gh auth git-credential' ls-remote "$url" refs/heads/main 2>/dev/null | cut -f1)
        [ "$before" = "$target" ] && { gum style --foreground 244 "  ✓ $name up to date (${target:0:12})"; exit 0; }
        # Full refname: a SHA source can't resolve a shortname destination on
        # a remote that doesn't have the branch yet (first push to a new repo).
        attempt=1
        while :; do
            out=$(git -c credential.helper= -c credential.helper='!gh auth git-credential' push "$url" "$target:refs/heads/main" 2>&1 || true)
            after=$(git -c credential.helper= -c credential.helper='!gh auth git-credential' ls-remote "$url" refs/heads/main 2>/dev/null | cut -f1)
            [ "$after" = "$target" ] && break
            # Diverged remote (e.g. autopilot lock commits landed since our last
            # fetch): recover in place — fetch, import, rebase our work onto
            # origin, re-advance main — and retry the push ONCE. Anything else
            # (signature, scope, protection) still fails immediately.
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

# --- Bootstrap ---

# Sync = bootstrap (clone any missing) + pull-all.
[group("Development")]
sync filter="":
    @just jj::bootstrap "{{filter}}"
    @just jj::pull-all "{{filter}}"

# Clone every sub-repo listed in kleinbem/repos.nix (in scope) and initialize
# jj on it. Never clones the three conductors themselves — you're already
# inside one to run this.
[group("Development")]
bootstrap filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh bootstrap {{filter}}

# One-time setup per repo: tell jj that main tracks main@origin.
[group("Development")]
init-bookmarks filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh init-bookmarks {{filter}}

[group("Development")]
branch-all name filter="":
    #!/usr/bin/env bash
    set -e
    gum confirm "🌿 Create bookmark '{{name}}' across the workspace?" || exit 0
    gum style --border normal --padding "0 2" --border-foreground 212 --foreground 212 "🌿 Creating bookmark '{{name}}'"
    targets=$({{_targets}} "{{filter}}" {{REPOS}} -- {{ALL_REPOS}})
    for repo in $targets; do
        name="$repo"
        gum spin --spinner dot --title "$name..." -- \
            bash -c "cd {{ROOT}}/$repo && jj bookmark create {{name}}"
    done
    gum style --foreground 46 --margin "1 0" "✅ Bookmark created."
