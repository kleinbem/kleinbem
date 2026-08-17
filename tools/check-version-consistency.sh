#!/usr/bin/env bash
# Pre-commit hook: Detect version pinning drift across the fleet
# Finds cases where the same package is pinned to different versions in different files

set -euo pipefail

# Search for version pinning patterns in Nix files
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Find all version assignments (platformToolsVersion, cmdLineToolsVersion, etc.)
grep -r "Version\s*=\s*\"[0-9]" . --include="*.nix" 2>/dev/null | \
  grep -E "(platform|build|tools|cmdLine).*Version" > "$TEMP_FILE" || true

if [ ! -s "$TEMP_FILE" ]; then
  exit 0  # No version pins found, all good
fi

# Extract package names and versions
declare -A versions
drift_found=0

while IFS=: read -r file assignment; do
  # Extract package name (before "Version")
  package=$(echo "$assignment" | sed -E 's/.*([a-zA-Z]+)Version.*/\1/')
  # Extract version (between quotes)
  version=$(echo "$assignment" | sed -E 's/.*"([^"]+)".*/\1/')

  if [ -z "$package" ] || [ -z "$version" ]; then
    continue
  fi

  # Check if we've seen this package before with a different version
  if [ -v "versions[$package]" ] && [ "${versions[$package]}" != "$version" ]; then
    if [ $drift_found -eq 0 ]; then
      echo "❌ Version pinning drift detected:"
      echo ""
      drift_found=1
    fi
    echo "  Package: $package"
    echo "    Pinned to ${versions[$package]} in: (earlier occurrence)"
    echo "    Pinned to $version in: $file"
    echo ""
  else
    versions[$package]=$version
  fi
done < "$TEMP_FILE"

if [ $drift_found -eq 1 ]; then
  echo "⚠️  Please update all occurrences to use the same version."
  echo ""
  echo "💡 Tip: Use 'just audit-versions <package>' to find all occurrences"
  exit 1
fi

exit 0
