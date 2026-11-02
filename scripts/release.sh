#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/test.sh
bash scripts/build.sh
app='build/轻右键.app'
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
if [[ "${GITHUB_REF:-}" == refs/tags/* ]] && [ "${GITHUB_REF_NAME}" != "v$version" ]; then
  printf 'Git 标签与应用版本不一致：%s / %s\n' "$GITHUB_REF_NAME" "$version" >&2
  exit 1
fi
bash scripts/package.sh
output="build/release/$version"
mkdir -p "$output"
cp "build/packages/轻右键-$version-macOS12-通用安装包.pkg" "$output/LocalRightClick-$version-universal.pkg"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/LocalRightClick-$version-universal.zip"
unzip -tqq "$output/LocalRightClick-$version-universal.zip"
cp CHANGELOG.md "$output/RELEASE_NOTES.md"
(
  cd "$output"
  shasum -a 256 "LocalRightClick-$version-universal.pkg" "LocalRightClick-$version-universal.zip" > SHA256SUMS.txt
)
printf 'Release files: %s/%s\n' "$(pwd)" "$output"
