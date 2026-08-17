#!/usr/bin/env bash
# Audit transitive dependency version changes in flake.lock
# Detects major version bumps in C libraries (FFmpeg, libssl, etc.)
# that could break dependent packages.
#
# Usage: audit-transitive-deps.sh [repo-path] [old-lock-file]

set -euo pipefail

REPO_PATH="${1:-.}"
OLD_LOCK="${2:-}"

# Critical transitive deps that often break dependents
WATCH_PACKAGES=(
  "ffmpeg"
  "openssl"
  "curl"
  "zlib"
  "libpng"
  "libjpeg"
  "lua"
  "python3"
  "perl"
  "postgresql"
  "libxml2"
)

# Helper: Extract nixpkgs revision from flake.lock
get_nixpkgs_rev() {
  local lock_file="$1"
  if [ ! -f "$lock_file" ]; then
    return 1
  fi
  jq -r '.nodes.nixpkgs.locked.rev' "$lock_file" 2>/dev/null || echo ""
}

# Helper: Get package version from nixpkgs at a given revision
get_package_version() {
  local pkg_name="$1"
  local nixpkgs_rev="$2"

  # Use nix eval to get the version
  nix eval --raw \
    "github:nixos/nixpkgs/$nixpkgs_rev#$pkg_name.version" \
    2>/dev/null || echo "unknown"
}

# Helper: Extract major version (e.g., "9.0.1" → "9")
get_major_version() {
  echo "$1" | cut -d. -f1
}

# Main audit
audit_transitive_deps() {
  local repo_path="$1"
  local lock_file="$repo_path/flake.lock"

  if [ ! -f "$lock_file" ]; then
    echo "❌ No flake.lock found at $lock_file"
    return 1
  fi

  local current_rev
  current_rev=$(get_nixpkgs_rev "$lock_file")

  if [ -z "$current_rev" ]; then
    echo "⚠️  Could not extract nixpkgs revision from flake.lock"
    return 1
  fi

  echo "📦 Auditing transitive dependencies for: $(basename "$repo_path")"
  echo "   nixpkgs rev: $current_rev"
  echo ""

  local has_changes=0

  for pkg in "${WATCH_PACKAGES[@]}"; do
    local current_version
    current_version=$(get_package_version "$pkg" "$current_rev" || echo "")

    if [ -z "$current_version" ] || [ "$current_version" = "unknown" ]; then
      continue
    fi

    local current_major
    current_major=$(get_major_version "$current_version")

    # If old lock provided, compare versions
    if [ -n "$OLD_LOCK" ] && [ -f "$OLD_LOCK" ]; then
      local old_rev
      old_rev=$(get_nixpkgs_rev "$OLD_LOCK" || echo "")

      if [ -n "$old_rev" ] && [ "$old_rev" != "$current_rev" ]; then
        local old_version
        old_version=$(get_package_version "$pkg" "$old_rev" || echo "")

        if [ -n "$old_version" ] && [ "$old_version" != "unknown" ]; then
          local old_major
          old_major=$(get_major_version "$old_version")

          if [ "$old_major" != "$current_major" ]; then
            echo "⚠️  $pkg: major version bump ($old_major → $current_major)"
            echo "   old: $old_version, new: $current_version"
            has_changes=1
          fi
        fi
      fi
    else
      # Just report what we found
      echo "  $pkg: $current_version"
    fi
  done

  if [ $has_changes -eq 1 ]; then
    echo ""
    echo "⚠️  ATTENTION: Major version changes detected in transitive deps"
    echo "   Review build logs for compatibility issues (like FFmpeg 9.0 → waypipe)"
    return 1
  fi

  echo "✓ No major version bumps detected"
  return 0
}

audit_transitive_deps "$REPO_PATH" "$OLD_LOCK"
