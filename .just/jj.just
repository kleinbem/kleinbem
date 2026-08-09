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
        "sweep-merged     — report merged/dead local branches per repo" \
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
        sweep-merged*)      just jj::sweep-merged ;;
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

# Fetch+prune every repo in scope and report local branches other than
# main: merged (safe to forget) vs. unclear (needs a manual look) vs.
# `gh pr checkout` residue. Read-only — never deletes anything itself,
# prints the cleanup one-liner for whatever it flags.
[group("Status")]
sweep-merged filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh sweep-merged {{filter}}

# Sign every unsigned commit ahead of origin, in scope.
# Uses `git rebase --exec` rather than `jj sign` (more reliable).
# Auto-advances the local `main` bookmark to @ first if @ has a description
# and is ahead — so users can run `sign-unsigned` directly after `jj describe`
# without needing a redundant `push-all` to trigger the bookmark move.
# First operation per session may need a YubiKey PIN; cached thereafter.
[group("Sync")]
sign-unsigned filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh sign-unsigned {{filter}}

# --- Sync ---

# Fetch from origin in every repo in scope and rebase the working-copy change.
[group("Sync")]
pull-all filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh pull-all {{filter}}

# Describe (commit) dirty changes across the scope.
# Prompts for message via gum input if not given.
#   just jj::save-all "feat: stalwart container"
#   just jj::save-all                       # prompts
#   just jj::save-all "fix: qos" openwrt     # filtered to "openwrt"
[group("Sync")]
save-all message="" filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh save-all "{{message}}" {{filter}}

# Describe (commit) ONE repo only — the fan-out-free path for when other
# repos carry someone else's in-flight work (parallel agent session, open
# editor). Works with any repo name in the fleet, including "nix"/"openwrt"/
# "kleinbem" themselves.
#   just jj::save nix-packages "fix(langfuse): bump fetcher"
[group("Sync")]
save repo message:
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh save {{repo}} "{{message}}"

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
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh push-all {{filter}}

# --- Bootstrap ---

# Sync = bootstrap (clone any missing) + pull-all.
[group("Development")]
sync filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh sync {{filter}}

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
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh branch-all {{name}} {{filter}}
