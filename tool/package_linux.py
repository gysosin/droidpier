#!/usr/bin/env python3
"""Create Linux packages from one validated, executable-relative payload."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
from fetch_runtime import fetch
from prepare_runtime import prepare_linux
from dependency_inventory import write_inventory
from version import ROOT, release_version


def checksums(directory):
    lines = []
    for file in sorted(directory.rglob('*')):
        if file.is_file() and file.name != 'SHA256SUMS':
            if directory.resolve() == (ROOT / 'dist').resolve() and file.name in {'open-dex-agent.jar', 'android-dependencies.json'}:
                continue
            digest = hashlib.sha256(file.read_bytes()).hexdigest()
            lines.append(f'{digest}  {file.relative_to(directory).as_posix()}')
    (directory / 'SHA256SUMS').write_text('\n'.join(lines) + '\n')


def copytree(source, target):
    shutil.copytree(source, target, symlinks=True, dirs_exist_ok=True)


def main():
    v = release_version()
    version = v['version']
    stage = ROOT / '.release/linux'
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    bundle = stage / 'droidpier'
    copytree(ROOT / 'apps/desktop/build/linux/x64/release/bundle', bundle)
    resources = bundle / 'resources'
    (resources / 'android').mkdir(parents=True)
    payload = Path(os.environ.get('DROIDPIER_ANDROID_PAYLOAD_DIR', dist))
    inventory_path = write_inventory(payload)
    shutil.copy2(payload / f'droidpier-companion-{version}.apk', resources / 'android/companion.apk')
    agent = payload / 'open-dex-agent.jar'
    if not agent.exists():
        agent = ROOT / 'android/agent/build/outputs/open-dex-agent.jar'
    shutil.copy2(agent, resources / 'android/open-dex-agent.jar')
    runtime = Path(os.environ['SCRCPY_DIR']) if os.environ.get('SCRCPY_DIR') else prepare_linux()
    (resources / 'scrcpy').mkdir()
    for name in ['scrcpy', 'scrcpy-server', 'adb', 'LICENSE', 'scrcpy.png', 'scrcpy.1']:
        source = runtime / name
        if source.exists(): shutil.copy2(source, resources / 'scrcpy' / name)
    ffmpeg = Path(os.environ.get('DROIDPIER_FFMPEG', ROOT / '.tools/droidpier-runtime/ffmpeg/install/bin/ffmpeg'))
    (resources / 'ffmpeg').mkdir()
    shutil.copy2(ffmpeg, resources / 'ffmpeg/ffmpeg')
    for file in ['LICENSE', 'NOTICE']:
        shutil.copy2(ROOT / file, bundle / file)
    copytree(ROOT / 'licenses', resources / 'licenses')
    shutil.copy2(inventory_path, resources / 'licenses/dependencies.cdx.json')
    config = ROOT / '.tools/droidpier-runtime/ffmpeg/configure-arguments.txt'
    if config.exists():
        shutil.copy2(config, resources / 'licenses/ffmpeg-build.txt')
    subprocess.run([str(ffmpeg), '-v', 'error', '-f', 'h264', '-i', str(ROOT / 'tool/fixtures/gray-16x16.h264'),
                    '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-y', str(stage / 'probe.rgba')], check=True)
    if (stage / 'probe.rgba').stat().st_size != 1024:
        raise SystemExit('Decoder probe generated an invalid frame')
    checksums(bundle)
    inventory = {'bomFormat': 'CycloneDX', 'specVersion': '1.5', 'version': 1,
                 'metadata': {'component': {'type': 'application', 'name': 'DroidPier', 'version': version}},
                 'components': []}
    for file in sorted(bundle.rglob('*')):
        if file.is_file():
            inventory['components'].append({'type': 'file', 'name': file.relative_to(bundle).as_posix(),
                'hashes': [{'alg': 'SHA-256', 'content': hashlib.sha256(file.read_bytes()).hexdigest()}]})
    (dist / f'droidpier-{version}-linux-files.cdx.json').write_text(json.dumps(inventory, indent=2) + '\n')
    with tarfile.open(dist / f'droidpier-{version}-linux-x86_64.tar.gz', 'w:gz') as archive:
        archive.add(bundle, arcname='droidpier')

    # System packages share the identical application payload, installed in /opt.
    package = stage / 'package'
    copytree(bundle, package / 'opt/droidpier')
    (package / 'usr/bin').mkdir(parents=True)
    (package / 'usr/bin/droidpier').symlink_to('/opt/droidpier/droidpier')
    for directory, source in [
        ('usr/share/applications', ROOT / 'tool/linux/droidpier.desktop'),
        ('usr/share/icons/hicolor/256x256/apps', ROOT / 'apps/desktop/assets/branding/droidpier-256.png'),
        ('usr/share/metainfo', ROOT / 'tool/linux/io.github.gysosin.droidpier.metainfo.xml'),
    ]:
        target = package / directory
        target.mkdir(parents=True)
        shutil.copy2(source, target / ('droidpier.png' if source.suffix == '.png' else source.name))
    control = package / 'DEBIAN'
    control.mkdir()
    (control / 'control').write_text(f'''Package: droidpier
Version: {v['debian']}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: DroidPier Contributors <gysosin@users.noreply.github.com>
Depends: libc6 (>= 2.35), libgtk-3-0, libstdc++6, libglu1-mesa, libudev1, libegl1, libgles2, libgl1
Homepage: https://github.com/gysosin/droidpier
Description: Android desktop workspace
 Your Android. A bigger workspace.
''')
    subprocess.run(['dpkg-deb', '--root-owner-group', '--build', str(package),
                    str(dist / f'droidpier-{version}-linux-amd64.deb')], check=True)
    shutil.rmtree(control)
    rpmdir = stage / 'rpmbuild'
    for folder in ['BUILD', 'BUILDROOT', 'RPMS', 'SOURCES', 'SPECS', 'SRPMS']:
        (rpmdir / folder).mkdir(parents=True)
    spec = rpmdir / 'SPECS/droidpier.spec'
    spec.write_text(f'''Name: droidpier
Version: {v['rpmVersion']}
Release: {v['rpmRelease']}
Summary: Android desktop workspace
License: Apache-2.0 AND LGPL-2.1-or-later AND MIT AND BSD-3-Clause AND OFL-1.1
URL: https://github.com/gysosin/droidpier
BuildArch: x86_64
Requires: gtk3, libstdc++, mesa-libGLU, libEGL.so.1()(64bit), libGLESv2.so.2()(64bit), libGL.so.1()(64bit), systemd-libs, glibc >= 2.35
AutoReqProv: no
%description
Your Android. A bigger workspace.
%install
mkdir -p %{{buildroot}}
cp -a "{package}/." %{{buildroot}}/
%files
/opt/droidpier
/usr/bin/droidpier
/usr/share/applications/droidpier.desktop
/usr/share/icons/hicolor/256x256/apps/droidpier.png
/usr/share/metainfo/io.github.gysosin.droidpier.metainfo.xml
''')
    subprocess.run(['rpmbuild', '--define', f'_topdir {rpmdir}', '--define', '_build_id_links none',
                    '--define', '__os_install_post %{nil}', '-bb', str(spec)], check=True)
    rpm = next((rpmdir / 'RPMS').rglob('*.rpm'))
    shutil.copy2(rpm, dist / f'droidpier-{version}-linux-x86_64.rpm')

    appdir = stage / 'DroidPier.AppDir'
    copytree(bundle, appdir / 'usr/lib/droidpier')
    shutil.copy2(ROOT / 'tool/linux/droidpier.desktop', appdir / 'droidpier.desktop')
    shutil.copy2(ROOT / 'apps/desktop/assets/branding/droidpier-256.png', appdir / 'droidpier.png')
    (appdir / 'AppRun').write_text('''#!/bin/sh
set -eu
appdir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$appdir/usr/lib/droidpier/droidpier" "$@"
''')
    (appdir / 'AppRun').chmod(0o755)
    tool = fetch('appimagetool-linux-x64')
    tool.chmod(0o755)
    subprocess.run([str(tool), '--appimage-extract-and-run', '--runtime-file', str(fetch('appimage-runtime-linux-x64')), str(appdir),
                    str(dist / f'droidpier-{version}-linux-x86_64.AppImage')],
                   env={**os.environ, 'ARCH': 'x86_64'}, check=True)
    checksums(dist)
    print('Linux packages created. Publication still requires license and compatibility acceptance.')


if __name__ == '__main__':
    main()
