#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_app="$(pwd)/build/轻右键.app"
target_app='/Applications/轻右键.app'
if pgrep -u "$(id -u)" -x LocalRightClick >/dev/null; then
  printf '请先从菜单栏退出轻右键，再运行安装。文件操作进行中时请等待完成。\n' >&2
  exit 1
fi
codesign --verify --deep --strict "$source_app"
mkdir -p build/archives
if [ -e "$target_app" ]; then
  installed_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$target_app/Contents/Info.plist")
  [ "$installed_id" = 'local.liudong.LocalRightClick' ] || { printf '同名位置不是轻右键，已停止安装。\n' >&2; exit 1; }
  ditto -c -k --sequesterRsrc --keepParent "$target_app" build/archives/previous-version.zip
  unzip -tqq build/archives/previous-version.zip
  pluginkit -e ignore -i local.liudong.LocalRightClick.Finder
fi
ditto "$source_app" "$target_app"
codesign --verify --deep --strict "$target_app"
ditto -c -k --sequesterRsrc --keepParent "$source_app" build/archives/current-build.zip
unzip -tqq build/archives/current-build.zip
if ! /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$source_app"; then
  printf '构建副本未能注销，将移除副本并重新注册正式版。\n' >&2
fi
rm -rf "$source_app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target_app"
pluginkit -a "$target_app/Contents/PlugIns/LocalRightClickFinder.appex"
pluginkit -e use -i local.liudong.LocalRightClick.Finder
open "$target_app"
printf '已安装到 %s。若菜单未出现，请在应用内点击“管理右键扩展”。\n' "$target_app"
