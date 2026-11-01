import 'common.just'

set working-directory := "."
export JJ_PAGER := "cat"

# --- Workspace VCS operations (jj-first) ---
# Canonical copy: nix/.just/jj.just and openwrt/.just/jj.just are symlinks to
# this file. With no filter a recipe covers every repo in repos.nix; a filter
# substring-matches repo names (tools/resolve-targets.sh). Recipes need `gum`.
# jj signs commits itself; sign-unsigned re-signs whatever is left unsigned.

# --- Interactive hub ---

# Interactive launcher: fuzzy-pick a workspace operation.
[group("Status")]
hub:
    #!/usr/bin/env bash
    set -e
    choice=$(gum choose --header "📦 Workspace Operations ({{file_name(justfile_directory())}})" \
        "ship-all         — describe + sign + push (the everything button)" \
        "─────────────────────────────────────────────" \
        "status-all       — repo state + ahead-of-origin counts" \
        "clean            — is everything clean? dirty/unpushed/workspaces/PRs/branches" \
        "abandon-merged   — drop local copies of changes already on main (proven only)" \
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
        clean*)             just jj::clean ;;
        abandon-merged*)    just jj::abandon-merged ;;
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

# Per repo: change id, @ state and commits ahead of origin/main.
[group("Status")]
status-all filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh status-all {{filter}}

# Flags: --local skips GitHub, --strict exits 1 when anything is unclean.

# Is the fleet clean enough to start new work? One row per repo plus a verdict.
[group("Status")]
clean *args="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh clean {{args}}

# GitHub dashboard per repo: origin/main SHA, CI status, open PRs and issues (~6s).
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

# Working-copy diff of every dirty repo; extra args go to `jj diff`.
[group("Status")]
diff-all filter="" *args="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh diff-all {{filter}} {{args}}

# Only unsigned commits fail (GitHub rejects them); unverified ones are only flagged.

# Audit commits ahead of origin for missing signatures.
[group("Status")]
check-signatures filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh check-signatures {{filter}}

# Only proven cases go; conflicts, workspace @s and anything unproven stay.
# pull-all does this too.

# Drop local copies of changes already on main (--dry-run to just show them).
[group("Sync")]
abandon-merged *args="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh abandon-merged {{args}}

# Read-only: prints the cleanup commands instead of running them.

# Report local branches other than main: merged, unclear or `gh pr checkout` residue.
[group("Status")]
sweep-merged filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh sweep-merged {{filter}}

# Uses `git rebase --exec` (jj sign doesn't reliably drive a hardware key).
# no-link: not reported upstream yet.
# Advances main first, so it works right after `jj describe`.

# Sign every unsigned commit ahead of origin.
[group("Sync")]
sign-unsigned filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh sign-unsigned {{filter}}

# --- Sync ---

# Fetch + rebase every repo, then drop local copies of merged changes.
[group("Sync")]
pull-all filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh pull-all {{filter}}

# Describe dirty changes across the scope; prompts for the message if not given.
[group("Sync")]
save-all message="" filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh save-all "{{message}}" {{filter}}

# Describe one repo only, for when other repos hold someone else's in-flight work.
[group("Sync")]
save repo message:
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh save {{repo}} "{{message}}"

# Prompts for the message if not given; KLEINBEM_PERSONA works as with save-all.

# Describe every dirty repo, sign anything unsigned, push.
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
    # Only where a maintenance::update-local recipe exists (nix/ has one).
    if just --show maintenance::update-local >/dev/null 2>&1; then
        just maintenance::update-local
        just jj::save-all "chore: update flake lockfiles" "{{filter}}"
    fi
    just jj::sign-unsigned "{{filter}}"
    just jj::push-all "{{filter}}"
    gum style --foreground 46 --margin "1 0" "✅ Shipped."

alias ship := ship-all

# Push every repo in scope, advancing main to a described @ first.
[group("Sync")]
push-all filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh push-all {{filter}}

# --- Bootstrap ---

# Sync = bootstrap (clone any missing) + pull-all.
[group("Development")]
sync filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh sync {{filter}}

# Clone missing repos from repos.nix, set up jj, link the workspace-root files.
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

# --- Agent workspaces ---
# Each concurrent session gets its own jj working copy at <repo>.ws/<name>/, so
# one session's `jj new`/`abandon` can't discard another's edits (`jj undo` still
# can: the op log is shared). Outside repos.nix, so *-all recipes skip them.
# jj-only (no .git); push works from there.

# e.g. `just jj::ws-new nix-config agentB -r <change-id>`; name defaults to ws-<time>-<rand>.

# Create a workspace for one repo and print the path to cd into.
[group("Agent workspaces")]
ws-new repo name="" *args="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh workspace-new {{repo}} {{name}} {{args}}

# List every open agent workspace fleet-wide (or filtered) with its @ state.
[group("Agent workspaces")]
ws-list filter="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh workspace-list {{filter}}

# Never touches real content; also reaps workspaces whose directory is gone.

# Forget + delete workspaces with no work of their own older than --hours (default 4).
[group("Agent workspaces")]
ws-gc filter="" *args="":
    @ROOT={{ROOT}} bash {{ROOT}}/kleinbem/tools/run-jj-fleet.sh workspace-gc {{filter}} {{args}}
