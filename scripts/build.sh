#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$(pwd)/build/轻右键.app"
extension="$app/Contents/PlugIns/LocalRightClickFinder.appex"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$extension/Contents/MacOS" build/module-cache
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
ditto Resources/BuiltInTemplates "$app/Contents/Resources/BuiltInTemplates"
for arch in arm64 x86_64; do
  swiftc -swift-version 5 -O -target "$arch-apple-macosx12.0" -module-cache-path build/module-cache Sources/Core.swift Sources/AppLaunch.swift Sources/LegacyLoginItem.swift Sources/App.swift Sources/TemplateManager.swift Sources/OpenApplicationManager.swift -framework AppKit -framework FinderSync -o "build/LocalRightClick-$arch"
  swiftc -swift-version 5 -O -parse-as-library -target "$arch-apple-macosx12.0" -module-cache-path build/module-cache Sources/Core.swift Sources/AppLaunch.swift Sources/FinderExtension.swift -framework AppKit -framework FinderSync -Xlinker -e -Xlinker _NSExtensionMain -o "build/LocalRightClickFinder-$arch"
done
lipo -create build/LocalRightClick-arm64 build/LocalRightClick-x86_64 -output "$app/Contents/MacOS/LocalRightClick"
lipo -create build/LocalRightClickFinder-arm64 build/LocalRightClickFinder-x86_64 -output "$extension/Contents/MacOS/LocalRightClickFinder"
python3 - "$app" "$extension" <<'PY'
import plistlib, pathlib, sys
app, ext = map(pathlib.Path, sys.argv[1:])
common = dict(CFBundleInfoDictionaryVersion='6.0', CFBundleShortVersionString='1.1.1', CFBundleVersion='3', CFBundleSupportedPlatforms=['MacOSX'], LSMinimumSystemVersion='12.0', NSPrincipalClass='NSApplication', LSUIElement=True, CFBundleDevelopmentRegion='zh_CN')
host = dict(common, CFBundleIdentifier='local.liudong.LocalRightClick', CFBundleExecutable='LocalRightClick', CFBundleName='轻右键', CFBundleDisplayName='轻右键', CFBundleIconFile='AppIcon', CFBundlePackageType='APPL', NSHumanReadableCopyright='LocalRightClick — local personal utility')
extension = dict(common, CFBundleIdentifier='local.liudong.LocalRightClick.Finder', CFBundleExecutable='LocalRightClickFinder', CFBundleName='轻右键 Finder 扩展', CFBundleDisplayName='轻右键 Finder 扩展', CFBundlePackageType='XPC!', NSExtension=dict(NSExtensionPointIdentifier='com.apple.FinderSync', NSExtensionPrincipalClass='LocalRightClickFinder', NSExtensionAttributes={}))
for base, data in [(app, host), (ext, extension)]:
    (base/'Contents'/'Info.plist').write_bytes(plistlib.dumps(data))
entitlements = {'com.apple.security.app-sandbox': True, 'com.apple.security.temporary-exception.files.home-relative-path.read-write': ['/Library/Application Support/LocalRightClick/']}
pathlib.Path('build/extension.entitlements').write_bytes(plistlib.dumps(entitlements))
PY
codesign --force --sign - --entitlements build/extension.entitlements "$extension"
codesign --force --sign - "$app"
codesign --verify --deep --strict --verbose=2 "$app"
python3 Tests/check_bundle.py
printf 'Built: %s\n' "$app"
