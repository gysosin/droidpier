#!/usr/bin/env python3
"""Collect pinned dependency sources beside release binaries for review."""
import json
from pathlib import Path
import shutil
import tarfile
from fetch_runtime import fetch
from package_linux import checksums
from version import ROOT, release_version


def main():
    version = release_version()['version']
    stage = ROOT / '.release/corresponding-source'
    if stage.exists(): shutil.rmtree(stage)
    stage.mkdir(parents=True)
    keys = ['ffmpeg-source', 'scrcpy-source', 'sdl-source', 'dav1d-source', 'libusb-source', 'appimage-runtime-source']
    for key in keys:
        source = fetch(key)
        shutil.copy2(source, stage / source.name)
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
SDL, dav1d and libusb archives match those pins.

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
