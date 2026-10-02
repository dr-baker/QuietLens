#!/usr/bin/env bash
# Package a local archive. Publishing remains an explicit gh release command.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:?Usage: bash scripts/release.sh VERSION}"
configured_version="$(sed -n 's/^    MARKETING_VERSION: "\(.*\)"$/\1/p' "$repo_dir/project.yml")"
if [[ "$version" != "$configured_version" ]]; then
  echo "Version $version does not match project.yml ($configured_version)." >&2
  exit 2
fi

mkdir -p "$repo_dir/build"
release_dir="$(mktemp -d "$repo_dir/build/release-${version}.XXXXXX")"
archive="$release_dir/QuietLens.xcarchive"
app="$archive/Products/Applications/Quiet Lens.app"
zip="$release_dir/QuietLens-${version}.zip"

signing_args=(CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO)
if [[ -n "${QUIET_LENS_SIGNING_TEAM:-}" ]]; then
  signing_args=(
    CODE_SIGN_STYLE=Manual
    "DEVELOPMENT_TEAM=$QUIET_LENS_SIGNING_TEAM"
    "CODE_SIGN_IDENTITY=${QUIET_LENS_SIGNING_IDENTITY:-Developer ID Application}"
    CODE_SIGNING_ALLOWED=YES
  )
fi

(cd "$repo_dir" && xcodegen generate)
xcodebuild -quiet -project "$repo_dir/QuietLens.xcodeproj" -scheme QuietLens \
  -configuration Release -archivePath "$archive" \
  -derivedDataPath "$repo_dir/.build/xcode" \
  -destination 'generic/platform=macOS' \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  "${signing_args[@]}" archive
ditto -c -k --keepParent "$app" "$zip"

echo "Artifact: $zip"
shasum -a 256 "$zip"
echo "This script does not notarize or publish the archive."
echo "Publish after verification:"
echo "  gh release create '$version' '$zip' --repo dr-baker/QuietLens --title 'Quiet Lens $version' --notes-file CHANGELOG.md"
