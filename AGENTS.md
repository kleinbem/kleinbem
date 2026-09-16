# kleinbem

Fleet hub — owns `repos.nix` (every fleet repo + its GitHub URL), the
canonical `.just/common.just` + `.just/jj.just` (symlinked into `nix/` and
`openwrt/`), and `tools/jj-fleet.sh` (the fleet dashboard). It's a
tooling-only conductor like `nix/`/`openwrt/`, except it also has a
`flake.nix` — that's for packaging the dashboard itself, not for any real
Nix config.

Note: `README.md` in this repo is still the unedited GitHub-profile
placeholder template (this repo doubles as the `kleinbem/kleinbem`
special profile repo) — it does not document this repo's actual purpose.
This file, and the root workspace `CLAUDE.md`, are the real orientation.

## Layout

| Path | What lives here |
|---|---|
| `repos.nix` | Every fleet repo + GitHub URL — single source of truth for `just bootstrap`/dashboard/fan-out. |
| `.just/common.just`, `.just/jj.just` | Canonical fleet-wide `just` recipes, symlinked into `nix/` and `openwrt/`. |
| `tools/jj-fleet.sh` | Dashboard implementation; fans out to `jj-toolbox`'s per-repo scripts rather than reimplementing jj primitives. |
| `tools/resolve-targets.sh` | Filter-matching logic every `*-all` recipe uses — has real tests. |
| `docs/` | ADRs and maintenance runbooks (e.g. `ADR-WAYPIPE-PLATFORM-SEPARATION.md`, `MAINTENANCE-RUNBOOKS.md`). |
| `tests/` | `bash kleinbem/tests/test-*.sh`, or `just test` from this repo. |

## Conventions

- This is a tooling-only repo — real Nix/OpenWrt work happens in the sibling repos it fans out to, never here.
- Changes to `.just/common.just`/`.just/jj.just` affect `nix/` and `openwrt/` too (symlinked, not copied) — check both conductors after editing.
- Run `cd kleinbem && just test` after touching `tools/resolve-targets.sh` or the fan-out logic.
