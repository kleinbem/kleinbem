# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this directory is

`~/Develop/github.com/kleinbem/` (the **workspace root**) is **not itself a git/jj repo**. It is a flat directory of ~16 independent sibling repos that together make up the "kleinbem fleet" — personal NixOS infrastructure, OpenWrt router infrastructure, and the tooling that glues them together. There are no git submodules; every subdirectory below is its own standalone git+jj repo, cloned side by side.

The root's own files (this `CLAUDE.md`, `justfile`, `.envrc`) are symlinks into `kleinbem/root/` — edit them there, in the kleinbem repo. `just bootstrap` creates the links when they're missing.

Always `cd` into the specific repo you need to work in — most real work (editing code, running builds/tests/linters) happens inside one of the sibling repos, each of which has its own `CLAUDE.md`/`AGENTS.md` with repo-specific detail. This root file is for orientation and for fleet-wide operations that span multiple repos at once.

## The three conductors

Three repos act as "meta-workspace" entry points — orchestrators with no `flake.nix` of their own (except `kleinbem/`, which does have one, for packaging the fleet dashboard):

- **`kleinbem/`** — the fleet hub. Owns `repos.nix` (the single source of truth listing every repo + its GitHub URL), the canonical `.just/common.just` and `.just/jj.just` (symlinked into `nix/` and `openwrt/`), and `tools/jj-fleet.sh` (the dashboard implementation, packaged via its `flake.nix`). Per-repo jj primitives (describe+advance, push/pull with the oauth-hang workaround, signing, workspaces, merged-branch sweep) aren't duplicated in `jj-fleet.sh` — it fans out to and aggregates `jj-toolbox`'s scripts; see below.
- **`nix/`** — conductor for the Nix/NixOS side. Real work happens in `nix-config` (hosts, modules, inventory — **start here** for NixOS questions), `nix-presets` (shared service/desktop bundles), `nix-hardware`, `nix-devshells`, `nix-packages`, `nix-templates`. It also owns `nix/infra/` — live OpenTofu/Terraform for Cloudflare, GitHub secrets, Google, netbird, and garage (see "Infrastructure as Code placement" below for why this lives here rather than its own repo).
- **`openwrt/`** — conductor for the router side, mirroring `nix/`. Real work happens in `openwrt-builder` (firmware image generation, pinned OpenWrt release, profile `bpi-r4`) and `openwrt-config` (Ansible-driven runtime config).

Other top-level repos: `github-config` (Terraform-managed GitHub org settings/rulesets/labels for all `kleinbem` repos), `kleinbem-secrets` (the sops/age-encrypted secrets store for the whole fleet — nix, openwrt, CI/infra, personas), `jj-toolbox` (single-repo jj helpers — `jj-save`, `jj-push`, `jj-pull`, `jj-abandon-merged`, `jj-sign-unsigned`, `jj-check-signatures`, `jj-sweep-merged`, `jj-ahead`, `jj-ws-new`/`ws-list`/`ws-gc` — each runs against whatever repo you're `cd`'d into, no `repos.nix` dependency; `kleinbem/tools/jj-fleet.sh` calls these per-repo rather than reimplementing the logic itself), `actions` (shared composite GitHub Actions — `nix-setup` installs Determinate Nix and, with the secrets, joins NetBird and reads the mesh-only Attic cache; every nix repo's workflows pin it by sha, Dependabot bumps it), `nix-toolbox` (generic Nix flake dev-workflow tools — `nix-check-versions`, `nix-audit-deps`, `nix-audit-locks`, `nix-verify-devshells`, `nix-check-lock`, `bash-test-lib.sh` — same "runs against whatever you point it at, no fleet dependency" philosophy as `jj-toolbox`). `nix-secrets` and `openwrt-secrets` (the legacy per-domain secrets repos `kleinbem-secrets` replaced) are fully retired — not in `repos.nix`, not on disk.

`nix-config/inventory.nix` is the master inventory for **both** NixOS and OpenWrt infrastructure — `openwrt-config/ansible/inventory.ini` is generated from it, never hand-edited.

`INFRASTRUCTURE.yaml` (at the workspace root, symlinked to `nix-config/docs/INFRASTRUCTURE.yaml`) is the auto-generated **Primary Ground Truth** for AI assistants. It compiles the entire multi-repo configuration into a single, structured YAML file covering hosts, hardware specs, Disko/impermanence storage, all ~30 container services, network routes, system modules, personas, and secrets. **Read this file first** to understand the fleet before diving into individual `.nix` files. Regenerate via `just maintenance::sync-agent`.

## Infrastructure as Code placement

When adding new Terraform/OpenTofu (or similar IaC), where it lives depends on whether it's self-contained:

- **Self-contained** — no dependency on another repo's generated data — gets its **own dedicated repo**. `github-config` is the example: it manages GitHub org/repo settings entirely from its own inputs.
- **Data-bridge-coupled** — consumes files generated from another repo's canonical source of truth — **stays co-located with the repo that owns that source of truth**, so the bridge is an in-repo path contract instead of a cross-repo one that can silently drift. `nix/infra/` is the example: `nix-config/iac/data.nix` generates `infra/personas.json` + `infra/inventory.json` from `inventory.nix`/`personas.nix`, and several `.tf` roots there consume those files directly by path.

Don't default to "every IaC root gets its own repo" — that's only right for the self-contained case. Splitting a data-bridge-coupled root into a separate repo turns a same-repo file dependency into a fragile cross-repo one for no benefit.

## Fleet-wide commands

Every conductor (and this root) exposes the same `just` recipes via the shared `.just/jj.just` module, all backed by `kleinbem/tools/jj-fleet.sh`. Run from anywhere in the workspace:

```bash
just                    # interactive fzf hub (gum-based) — the easiest entry point
just status-all [filter]     # repo state + ahead-of-origin counts
just clean [filter] [--local] [--strict]  # all-clean check: dirty/unpushed/conflicts/jj workspaces/PRs/issues/extra branches + verdict
just abandon-merged [filter] [--dry-run]  # drop local copies of changes already on main (proven only); pull-all does this too
just diff-all [filter]       # uncommitted changes across the fleet
just remote-status [filter]  # GitHub dashboard: CI, PRs, issues (~6s, hits gh API)
just remote-prs [filter]     # open PRs across the fleet
just remote-ci [n] [filter]  # recent CI runs per repo
just check-signatures [filter]  # audit commit signatures ahead of origin
just save-all "msg" [filter]    # jj describe in every dirty repo
just push-all [filter]          # push every repo
just pull-all [filter]          # fetch + rebase every repo, then abandon-merged
just sign-unsigned [filter]     # sign unsigned commits ahead of origin (touches YubiKey)
just ship-all "msg" [filter]    # save-all + sign-unsigned + push-all in one shot (alias: ship)
just bootstrap [filter]         # clone any repo from repos.nix that's missing on disk
just init-bookmarks [filter]    # point local main at main@origin (one-time per repo)
just in <repo> <recipe>         # pass through to a specific repo's own justfile,
                                 #   e.g. `just in nix-config nixos::switch`
```

`filter` substring-matches repo names fleet-wide (e.g. `just status-all nix` hits every `nix*` repo from any location, including from inside `openwrt/`). No filter = every repo in `repos.nix`.

**VCS is jj-first.** [Jujutsu](https://jj-vc.github.io/jj/) is the primary interface (colocated with git in every repo); use raw `git` only for legacy rescue operations or destructive resets that aren't wrapped by the `jj::*` recipes.

**Every PR auto-merges.** Right after `gh pr create`, run `gh pr merge --auto --squash` on it, so a PR that goes green merges without anyone coming back to it (review happens while CI runs). Public repos also require the CodeRabbit review and resolved conversations, so answer every CodeRabbit thread before walking away (agent-ops skill). Open a draft when a change must be held. Required checks are non-strict (github-config), so a PR that fell behind main still merges; if one must be brought up to date, use `gh pr update-branch` without `--rebase`: GitHub's rebase can drop commit signatures, and every default branch requires signed commits. Exceptions: private repos (kleinbem-secrets, mesh-llm-gpu) can't keep auto-merge on this plan, so merge those by hand once green; skills requires its `check` job (skill structure + `claude plugin validate`, `just check` locally).

Fresh machine setup: `just bootstrap` clones every missing repo from `kleinbem/repos.nix`. If you're starting from a fresh clone of just `nix/` or `openwrt/` (not `kleinbem/`), run `bash tools/bootstrap.sh` inside that repo first — `just` can't parse until `kleinbem/` exists, since the shared `.just/` modules are symlinks into it.

Tests for the shared fan-out tooling itself (`kleinbem/tools/resolve-targets.sh`, the filter-matching logic used by every `*-all` recipe) live in `kleinbem/tests/`:

```bash
cd kleinbem && just test              # runs every kleinbem/tests/test-*.sh
bash kleinbem/tests/test-resolve-targets.sh   # run a single test file directly
```

## Multi-agent jj workflow

**Every agent session that edits a repo works in its own jj workspace. The primary checkout (`<repo>/`) belongs to Martin.** jj snapshots `@` on nearly every command, so two sessions sharing one working copy silently discard or move each other's edits with any `jj new`/`abandon`/`undo`/`restore`; and sessions that finish in the primary checkout leave their commits, bookmarks and half-edits behind there. The 2026-10-24 clean-up found 71 such leftovers.

```bash
just jj::ws-new <repo> [name]            # creates <repo>.ws/<name>/ on main, prints the path — cd there and work
just jj::ws-new <repo> <name> -r <change>  # start on an existing change (move work out of the primary checkout)
just jj::ws-list [filter]                # every open agent workspace and its @ state
just jj::ws-gc [filter] [--hours N]      # reap empty/undescribed workspaces older than N hours (default 4); never touches real content
```

- Claim the workspace as the first step, before reading or editing anything in the repo. If you find yourself with edits in the primary checkout, `jj describe` them, `just jj::ws-new <repo> <name> -r <that change>`, then `jj new main@origin` in the primary to hand it back empty.
- Added workspaces are jj-only (no `.git`) — use `jj`, not raw `git`, inside one. `jj git push`, `gh pr create` and `just jj::push-all` work from any workspace since the commit graph and git backend are shared. If you see "working copy is stale," run `jj workspace update-stale` (non-destructive).
- Finish from the workspace: `jj describe`, push, open the PR there. Once the PR merges, `just jj::ws-gc` reaps the workspace and `just pull-all` (or `just abandon-merged`) drops the local copy of the merged change; don't leave either for later.
- `just clean` is the fleet-wide check that nothing was left behind: dirty working copies, commits not in main, conflicts, open workspaces, PRs, extra branches.

## Secrets

`kleinbem-secrets` is the encrypted secrets repo for the whole fleet (sops + age, per-path scoped recipients — see its own README for the `.sops.yaml` model). It replaced the older per-domain `nix-secrets` / `openwrt-secrets` repos, both fully retired (removed from disk and `repos.nix`). Never assume a plaintext file in any `*-secrets` repo is fine just because the repo's stated purpose is encryption — verify before treating it as safe to read, edit, or reference.

## Environment

Each repo's `.envrc` loads a Nix devshell via direnv; the root `.envrc` and every sibling repo's `.envrc` ultimately load `nix-devshells#workspace` (or a domain-specific shell like `nix-devshells#openwrt`), which provides `just`, `jj`, `gh`, `gum`, `sops`, `age`, and other fleet tooling. If a tool like `colmena` seems to be missing from PATH, the devshell probably isn't loaded — check `direnv status` / `direnv allow` before assuming the tool needs installing.
