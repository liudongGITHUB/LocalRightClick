#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
archive='build/archives/current-build.zip'
[ -d 'build/轻右键.app' ] || [ -f "$archive" ] || { printf '请先运行 bash scripts/build.sh。\n' >&2; exit 1; }
staging=$(mktemp -d "${TMPDIR:-/tmp}/LocalRightClick-package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/root/Applications" build/packages
if [ -d 'build/轻右键.app' ]; then
  ditto 'build/轻右键.app' "$staging/root/Applications/轻右键.app"
else
  ditto -x -k "$archive" "$staging/root/Applications"
fi
app="$staging/root/Applications/轻右键.app"
codesign --verify --deep --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
python3 - "$staging" "$version" <<'PY'
import pathlib, plistlib, sys
import xml.etree.ElementTree as ET
stage, version = pathlib.Path(sys.argv[1]), sys.argv[2]
components = [dict(RootRelativeBundlePath='Applications/轻右键.app', BundleIsRelocatable=False,
                   BundleIsVersionChecked=True, BundleHasStrictIdentifier=True, BundleOverwriteAction='upgrade')]
(stage/'components.plist').write_bytes(plistlib.dumps(components))
root = ET.Element('installer-gui-script', minSpecVersion='2')
ET.SubElement(root, 'title').text = '轻右键'
ET.SubElement(root, 'options', **{'customize':'never', 'require-scripts':'false', 'hostArchitectures':'arm64,x86_64'})
ET.SubElement(root, 'domains', enable_anywhere='false', enable_currentUserHome='false', enable_localSystem='true')
ET.SubElement(root, 'welcome', file='welcome.html', **{'mime-type':'text/html'})
ET.SubElement(root, 'conclusion', file='conclusion.html', **{'mime-type':'text/html'})
volume = ET.SubElement(root, 'volume-check')
ET.SubElement(ET.SubElement(volume, 'allowed-os-versions'), 'os-version', min='12.0')
ET.SubElement(ET.SubElement(root, 'choices-outline'), 'line', choice='app')
choice = ET.SubElement(root, 'choice', id='app', title='轻右键', description='安装轻右键及 Finder 扩展', visible='false')
identifier = 'local.liudong.LocalRightClick.pkg'
ET.SubElement(choice, 'pkg-ref', id=identifier)
ET.SubElement(root, 'pkg-ref', id=identifier, version=version, onConclusion='None').text = 'LocalRightClick.pkg'
ET.SubElement(ET.SubElement(ET.SubElement(root, 'pkg-ref', id=identifier), 'must-close'), 'app', id='local.liudong.LocalRightClick')
ET.ElementTree(root).write(stage/'Distribution.xml', encoding='utf-8', xml_declaration=True)
PY
pkgbuild --root "$staging/root" --component-plist "$staging/components.plist" --scripts Installer/Scripts --identifier local.liudong.LocalRightClick.pkg --version "$version" --install-location / "$staging/LocalRightClick.pkg"
output="build/packages/轻右键-$version-macOS12-通用安装包.pkg"
productbuild --distribution "$staging/Distribution.xml" --package-path "$staging" --resources Installer/Resources "$output"
python3 Tests/check_package.py "$output"
printf '安装包：%s/%s\n' "$(pwd)" "$output"
