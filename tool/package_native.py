#!/usr/bin/env python3
"""Stage signed Android payloads for experimental Windows and macOS packages."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import zipfile
from version import ROOT, release_version
from package_linux import checksums, copytree


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('platform', choices=['windows', 'macos'])
    args = parser.parse_args()
    v = release_version()['version']
    stage = ROOT / '.release' / args.platform
    if stage.exists(): shutil.rmtree(stage)
    stage.mkdir(parents=True)
    dist = ROOT / 'dist'; dist.mkdir(exist_ok=True)
    if args.platform == 'windows':
        app = stage / 'droidpier'
        copytree(ROOT / 'apps/desktop/build/windows/x64/runner/Release', app)
        resources = app / 'resources'
    else:
        app = stage / 'DroidPier.app'
        copytree(ROOT / 'apps/desktop/build/macos/Build/Products/Release/DroidPier.app', app)
        resources = app / 'Contents/MacOS/resources'
    runtime = Path(os.environ['SCRCPY_DIR'])
    ffmpeg = Path(os.environ['DROIDPIER_FFMPEG'])
    payload = Path(os.environ.get('DROIDPIER_ANDROID_PAYLOAD_DIR', ROOT / 'dist'))
    (resources / 'android').mkdir(parents=True)
    copytree(runtime, resources / 'scrcpy')
    (resources / 'ffmpeg').mkdir()
    suffix = '.exe' if args.platform == 'windows' else ''
    shutil.copy2(ffmpeg, resources / ('ffmpeg/ffmpeg' + suffix))
    if args.platform == 'macos' and os.environ.get('ADB_PATH'):
        shutil.copy2(os.environ['ADB_PATH'], resources / 'scrcpy/adb')
    for executable in ['adb', 'scrcpy']:
        if not (resources / 'scrcpy' / (executable + suffix)).is_file():
            raise SystemExit(f'Missing bundled {executable}')
    shutil.copy2(payload / f'droidpier-companion-{v}.apk', resources / 'android/companion.apk')
    shutil.copy2(payload / 'open-dex-agent.jar', resources / 'android/open-dex-agent.jar')
    copytree(ROOT / 'licenses', resources / 'licenses')
    for name in ['LICENSE', 'NOTICE']: shutil.copy2(ROOT / name, resources / name)
    if args.platform == 'windows':
        # Optional Authenticode signing is provided by the maintainer's signing command.
        # It must sign both the application and final installer before checksumming.
        checksums(app)
        with zipfile.ZipFile(dist / f'droidpier-{v}-windows-x64.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
            for p in sorted(app.rglob('*')):
                if p.is_file(): archive.write(p, p.relative_to(stage))
        compiler = os.environ.get('ISCC', 'ISCC.exe')
        subprocess.run([compiler, f'/DReleaseVersion={v}', f'/DSourceDir={app}',
                        f'/DOutputDir={dist}', str(ROOT / 'tool/windows/droidpier.iss')], check=True)
    else:
        identity = os.environ.get('CODESIGN_IDENTITY', '-')
        subprocess.run(['codesign', '--force', '--deep', '--sign', identity, str(app)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        (stage / 'Applications').symlink_to('/Applications')
        architecture = os.uname().machine
        subprocess.run(['hdiutil', 'create', '-volname', 'DroidPier', '-srcfolder', str(stage),
                        '-ov', '-format', 'UDZO', str(dist / f'droidpier-{v}-macos-{architecture}.dmg')], check=True)
        # A Developer ID build may subsequently use xcrun notarytool and stapler.
    checksums(dist)
    print('Experimental packages created; native and real-device acceptance is still required.')

if __name__ == '__main__': main()
