#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checks_dir="$repo_dir/.build/checks"
mkdir -p "$checks_dir"

swiftc -parse-as-library \
  "$repo_dir/QuietLens/Core/OverviewDetector.swift" \
  "$repo_dir/Tests/OverviewDockIdentityCheck.swift" \
  -o "$checks_dir/overview-dock-identity"
"$checks_dir/overview-dock-identity"

# Checks do not require a signing identity or install the product.
QUIET_LENS_SIGNING_TEAM= bash "$repo_dir/scripts/build.sh" build
QUIET_LENS_SIGNING_TEAM= bash "$repo_dir/scripts/build.sh" analyze
