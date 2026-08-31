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
    for key in keys:
        source = fetch(key)
        copy_distribution_source(key, source, stage)
    recipes = stage / 'build-recipes'; recipes.mkdir()
    for name in ['runtime-lock.json', 'build_ffmpeg.sh', 'linux/Dockerfile']:
        target = recipes / name; target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / 'tool' / name, target)
    config = ROOT / '.tools/droidpier-runtime/ffmpeg/configure-arguments.txt'
    if config.exists(): shutil.copy2(config, recipes / 'ffmpeg-configure-arguments.txt')
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

This collection is a review input, not a complete redistribution attestation.
The maintainer must also verify ADB provenance, AppImage runtime sources, Flutter
notices and all linked system/native libraries against the actual shipped files.
Do not publish binaries until the release acceptance license audit is complete.
''')
    checksums(stage)
    target = ROOT / 'dist' / f'droidpier-{version}-dependency-sources.tar.gz'
    with tarfile.open(target, 'w:gz') as archive: archive.add(stage, arcname='dependency-sources')
    checksums(ROOT / 'dist')
    print(target.name)

if __name__ == '__main__': main()
