#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
workspace_dir="${project_dir:h:h}"
signing_key="${PEEKFORGE_SIGNING_KEY:-$workspace_dir/work/peekforge-signing-private.key}"
release_dir="$workspace_dir/work/release"
if [[ ! -f "$signing_key" ]]; then
  print -u2 "Signing key missing: $signing_key"
  exit 1
fi
if [[ -n "$(git -C "$project_dir" status --porcelain)" ]]; then
  print -u2 "Commit source changes before publishing a release."
  exit 1
fi
"$project_dir/build-local.sh"
mkdir -p "$release_dir"
archive="$release_dir/PeekForge-macOS.zip"
signature="$release_dir/PeekForge-macOS.sig"
ditto -c -k --sequesterRsrc --keepParent "$project_dir/../PeekForge.app" "$archive"
swiftc -parse-as-library "$project_dir/Tools/SignRelease.swift" -o "$release_dir/sign-release"
"$release_dir/sign-release" --sign "$signing_key" "$archive" "$signature"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/../PeekForge.app/Contents/Info.plist")
git -C "$project_dir" push origin HEAD:main
gh release create "v$version" "$archive" "$signature" --repo blackowltr/PeekForge --target "$(git -C "$project_dir" rev-parse HEAD)" --title "PeekForge $version" --notes "PeekForge macOS release $version. Download the ZIP, move PeekForge.app to Applications, then open it once to enable automatic updates."
