import pathlib
import plistlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

with tempfile.TemporaryDirectory(prefix='LRC-package-check-') as directory:
    expanded = pathlib.Path(directory) / 'expanded'
    subprocess.run(['pkgutil', '--expand-full', sys.argv[1], str(expanded)], check=True)
    distribution = ET.parse(expanded / 'Distribution').getroot()
    assert distribution.find('volume-check/allowed-os-versions/os-version').get('min') == '12.0'
    assert set(distribution.find('options').get('hostArchitectures').split(',')) == {'arm64', 'x86_64'}
    assert distribution.find('domains').get('enable_currentUserHome') == 'false'
    assert distribution.find('pkg-ref/must-close/app').get('id') == 'local.liudong.LocalRightClick'
    component = expanded / 'LocalRightClick.pkg'
    metadata = ET.parse(component / 'PackageInfo').getroot()
    assert metadata.get('install-location') == '/'
    assert metadata.get('identifier') == 'local.liudong.LocalRightClick.pkg'
    bundle = metadata.find('bundle')
    assert pathlib.PurePosixPath(bundle.get('path')) == pathlib.PurePosixPath('Applications/轻右键.app')
    assert metadata.get('relocatable') == 'false'
    assert not metadata.findall('relocate/bundle')
    assert metadata.find('upgrade-bundle/bundle').get('id') == 'local.liudong.LocalRightClick'
    assert metadata.find('strict-identifier/bundle').get('id') == 'local.liudong.LocalRightClick'
    payload = component / 'Payload'
    assert {p.name for p in payload.iterdir()} == {'Applications'}
    assert {p.name for p in (payload / 'Applications').iterdir()} == {'轻右键.app'}
    app = payload / 'Applications/轻右键.app'
    extension = app / 'Contents/PlugIns/LocalRightClickFinder.appex'
    for base, name in [(app, 'LocalRightClick'), (extension, 'LocalRightClickFinder')]:
        info = plistlib.loads((base / 'Contents/Info.plist').read_bytes())
        assert info['LSMinimumSystemVersion'] == '12.0'
        assert info['CFBundleShortVersionString'] == metadata.get('version')
        executable = base / 'Contents/MacOS' / name
        assert set(subprocess.check_output(['lipo', '-archs', str(executable)], text=True).split()) == {'arm64', 'x86_64'}
        for arch in ['arm64', 'x86_64']:
            commands = subprocess.check_output(['otool', '-arch', arch, '-l', str(executable)], text=True)
            assert re.search(r'minos 12\.0\b', commands)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    script = component / 'Scripts/preinstall'
    assert script.read_bytes() == pathlib.Path('Installer/Scripts/preinstall').read_bytes()
    assert not (component / 'Scripts/postinstall').exists()
    for name in ['welcome.html', 'conclusion.html']:
        assert list((expanded / 'Resources').rglob(name))
print('PASS installer destination, OS/CPU requirements, payload, app signature, resources and upgrade guard')

with tempfile.TemporaryDirectory(prefix='LRC-preinstall-check-') as directory:
    volume = pathlib.Path(directory)
    script = pathlib.Path('Installer/Scripts/preinstall').resolve()
    def run():
        return subprocess.run(['/bin/bash', str(script), 'package.pkg', '/', str(volume)], capture_output=True, text=True)
    running = subprocess.run(['/usr/bin/pgrep', '-x', 'LocalRightClick'], capture_output=True).returncode == 0
    if running:
        assert run().returncode != 0
        assert '请先退出轻右键' in run().stderr
        print('PASS running app blocks replacement without termination')
    else:
        assert run().returncode == 0
        app = volume / 'Applications/轻右键.app'
        (app / 'Contents').mkdir(parents=True)
        info = app / 'Contents/Info.plist'
        info.write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.liudong.LocalRightClick'}))
        assert run().returncode == 0
        info.write_bytes(plistlib.dumps({'CFBundleIdentifier':'some.other.app'}))
        assert run().returncode != 0
        assert plistlib.loads(info.read_bytes())['CFBundleIdentifier'] == 'some.other.app'
        app.rename(app.with_name('original.app'))
        app.symlink_to(app.with_name('original.app'), target_is_directory=True)
        assert run().returncode != 0
        assert app.is_symlink()
        print('PASS fresh install and matching upgrade; unrelated app and symlink rejected')
