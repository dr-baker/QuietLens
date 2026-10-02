#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="${1:-build}"
case "$action" in
  build|analyze) ;;
  *) echo "Usage: bash scripts/build.sh [build|analyze]" >&2; exit 2 ;;
esac

# Use one path across rebuilds. Signing is optional and stays outside the repo.
derived_data="$repo_dir/.build/xcode"
signing_args=(CODE_SIGNING_ALLOWED=NO)
if [[ -n "${QUIET_LENS_SIGNING_TEAM:-}" ]]; then
  signing_args=(
    CODE_SIGN_STYLE=Manual
    "DEVELOPMENT_TEAM=$QUIET_LENS_SIGNING_TEAM"
    "CODE_SIGN_IDENTITY=${QUIET_LENS_SIGNING_IDENTITY:-Developer ID Application}"
    CODE_SIGNING_ALLOWED=YES
  )
fi

(cd "$repo_dir" && xcodegen generate)
xcodebuild -quiet \
  -project "$repo_dir/QuietLens.xcodeproj" -scheme QuietLens \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data" \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  "${signing_args[@]}" "$action"

if [[ "$action" == build ]]; then
  echo "Built $derived_data/Build/Products/Release/Quiet Lens.app"
fi
