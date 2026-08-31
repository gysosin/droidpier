#!/usr/bin/env python3
"""Unpack a checksum-verified scrcpy runtime without local SDK dependencies."""
from pathlib import Path
import shutil
import tarfile
from fetch_runtime import fetch
from version import ROOT


def prepare_linux():
    target = ROOT / '.tools/droidpier-runtime/scrcpy'
    source = fetch('scrcpy-linux-x64')
    target.mkdir(parents=True, exist_ok=True)
    with tarfile.open(source) as archive:
        # Flatten only the known files; do not trust archive paths or symlinks.
        allowed = {'scrcpy', 'scrcpy-server', 'adb', 'LICENSE', 'scrcpy.png', 'scrcpy.1'}
        for member in archive.getmembers():
            name = Path(member.name).name
            if member.isfile() and name in allowed:
                with archive.extractfile(member) as src, (target / name).open('wb') as dst:
                    shutil.copyfileobj(src, dst)
                (target / name).chmod(0o755 if name in {'scrcpy', 'adb'} else 0o644)
    for name in ['scrcpy', 'scrcpy-server', 'adb']:
        if not (target / name).exists(): raise SystemExit(f'Runtime lacks {name}')
    return target

if __name__ == '__main__': print(prepare_linux())
