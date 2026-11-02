import plistlib
import subprocess
import re
from pathlib import Path
from zipfile import ZipFile
import xml.etree.ElementTree as ET

app = Path('build/轻右键.app')
extension = app / 'Contents/PlugIns/LocalRightClickFinder.appex'
host_info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
icon = app / 'Contents/Resources' / (host_info['CFBundleIconFile'] + '.icns')
assert icon.read_bytes()[:4] == b'icns', 'Missing or invalid application icon'
for extension_name, document in [('docx', 'word/document.xml'), ('xlsx', 'xl/workbook.xml'), ('pptx', 'ppt/presentation.xml')]:
    with ZipFile(app / 'Contents/Resources/BuiltInTemplates' / ('blank.' + extension_name)) as archive:
        assert archive.testzip() is None
        for name in archive.namelist():
            if name.endswith(('.xml', '.rels')):
                ET.fromstring(archive.read(name))
        assert archive.read(document)
        ET.fromstring(archive.read('[Content_Types].xml'))
entitlements = plistlib.loads(Path('build/extension.entitlements').read_bytes())
assert entitlements['com.apple.security.app-sandbox'] is True
paths = entitlements['com.apple.security.temporary-exception.files.home-relative-path.read-write']
assert paths == ['/Library/Application Support/LocalRightClick/'], paths
info = plistlib.loads((extension / 'Contents/Info.plist').read_bytes())
assert info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.FinderSync'
assert info['NSExtension']['NSExtensionPrincipalClass'] == 'LocalRightClickFinder'
assert info['CFBundlePackageType'] == 'XPC!'
print('PASS bundle structure and scoped sandbox entitlement')

for bundle, executable in [(app, "LocalRightClick"), (extension, "LocalRightClickFinder")]:
    metadata = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    assert metadata["LSMinimumSystemVersion"] == "12.0"
    binary = bundle / "Contents/MacOS" / executable
    archs = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()
    assert set(archs) == {"arm64", "x86_64"}, archs
    for arch in archs:
        load_commands = subprocess.check_output(["otool", "-arch", arch, "-l", str(binary)], text=True)
        assert re.search(r"minos 12\.0\b", load_commands), (executable, arch)
print("PASS macOS 12 deployment target and both CPU slices for app and Finder extension")
