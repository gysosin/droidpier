#!/usr/bin/env python3
"""Collect pinned dependency sources beside release binaries for review."""
import json
from pathlib import Path
import shutil
import tarfile
from fetch_runtime import fetch
from package_linux import checksums
from version import ROOT, release_version


def copy_distribution_source(key, source, stage):
    if key != 'sdl-source':
        shutil.copy2(source, stage / source.name)
        return
    # Retain build documentation and credits, without optional repository guides.
    retained_guides = {'README.md', 'INSTALL.md', 'BUILD.md', 'CREDITS.md',
                       'LICENSE.md', 'COPYING.md', 'COPYRIGHT.md', 'NOTICE.md'}
    target = stage / (source.name.removesuffix('.tar.gz') + '-distribution-source.tar.gz')
    with tarfile.open(source) as original, tarfile.open(target, 'w:gz') as published:
        for member in original:
            path = Path(member.name)
            if len(path.parts) == 2 and path.suffix == '.md' and path.name not in retained_guides:
                continue
            published.addfile(member, original.extractfile(member) if member.isfile() else None)


def main():
    version = release_version()['version']
    stage = ROOT / '.release/corresponding-source'
    if stage.exists(): shutil.rmtree(stage)
    stage.mkdir(parents=True)
    keys = ['ffmpeg-source', 'scrcpy-source', 'sdl-source', 'dav1d-source', 'libusb-source',
            'appimage-runtime-source', 'libfuse-source', 'squashfuse-source']
    lock = json.loads((ROOT / 'tool/runtime-lock.json').read_text())
    keys += [key for key, item in lock.items()
             if item.get('sourceCollection') and key not in keys]
    for key in keys:
        source = fetch(key)
        destination = lock[key].get('sourcePath')
        if destination:
            target = stage / destination
            if not target.resolve().is_relative_to(stage.resolve()):
                raise SystemExit('Unsafe source collection path: ' + destination)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        else:
            copy_distribution_source(key, source, stage)
    recipes = stage / 'build-recipes'; recipes.mkdir()
    for name in ['runtime-lock.json', 'build_ffmpeg.sh', 'linux/Dockerfile']:
        target = recipes / name; target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'tool' / name, target)
    config = ROOT / '.tools/droidpier-runtime/ffmpeg/configure-arguments.txt'
    if config.exists(): shutil.copy2(config, recipes / 'ffmpeg-configure-arguments.txt')
    shutil.copy2(ROOT / 'docs/RUNTIME_PROVENANCE.md', stage / 'RUNTIME_PROVENANCE.md')
    (stage / 'README.txt').write_text('''DroidPier dependency source collection

The FFmpeg decoder uses the included build_ffmpeg.sh and unmodified pinned source.
No local FFmpeg source patches are applied. The scrcpy source archive includes
its app/deps scripts describing upstream binary builds and their dependency pins.
SDL, dav1d and libusb source versions match those pins.
The SDL distribution archive omits optional top-level repository guides; all
implementation, build files, API documentation, credits and license texts are
unchanged. Its original upstream archive checksum remains in runtime-lock.json;
SHA256SUMS records the separately repacked distribution archive.
The AppImage runtime's pinned libfuse and squashfuse sources are included. Its
source archive retains the libfuse patch and dependency build instructions.
The collection also includes its musl, zlib, zstd and mimalloc source inputs,
with the matching Alpine package recipes and patches under alpine/.
Ubuntu source packages include their .dsc checksum records and Debian/Ubuntu
patches and build rules. See RUNTIME_PROVENANCE.md for the scope of each input.

The source and recipe coverage is documented in RUNTIME_PROVENANCE.md. Original
license and copyright files remain in each source archive. Package notices also
cover ADB, the Flutter/Dart runtime, Android dependencies and fonts. The release
acceptance record separately tracks source review and installation/device tests;
providing dependency sources does not establish device compatibility.
''')
    checksums(stage)
    target = ROOT / 'dist' / f'droidpier-{version}-dependency-sources.tar.gz'
    with tarfile.open(target, 'w:gz') as archive: archive.add(stage, arcname='dependency-sources')
    checksums(ROOT / 'dist')
    print(target.name)

if __name__ == '__main__': main()
