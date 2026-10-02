#!/usr/bin/env bash
# Update the fork's version source and regenerate the Xcode project.
# The inherited Homebrew cask still targets upstream and is left unchanged.
set -euo pipefail

version="${1:?Usage: bash scripts/bump-version.sh VERSION [BUILD]}"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$repo_dir/project.yml"

if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "Version must contain three numeric components, for example 1.0.9." >&2
  exit 2
fi
current_build="$(sed -n 's/^    CURRENT_PROJECT_VERSION: "\([0-9]*\)"$/\1/p' "$project")"
if [[ ! "$current_build" =~ ^[1-9][0-9]*$ ]]; then
  echo "project.yml must contain a positive CURRENT_PROJECT_VERSION." >&2
  exit 2
fi
build="${2:-$((current_build + 1))}"
if [[ ! "$build" =~ ^[1-9][0-9]*$ ]]; then
  echo "Build must be a positive integer." >&2
  exit 2
fi
command -v xcodegen >/dev/null

/usr/bin/sed -i '' -E "s/(MARKETING_VERSION:[[:space:]]*\")[^\"]+\"/\1${version}\"/" "$project"
/usr/bin/sed -i '' -E "s/(CURRENT_PROJECT_VERSION:[[:space:]]*\")[^\"]+\"/\1${build}\"/" "$project"

(cd "$repo_dir" && xcodegen generate)

echo "Bumped to $version (build $build)."
echo "After verification: bash scripts/release.sh $version"
