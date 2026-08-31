#!/usr/bin/env python3
"""Validate release file completeness, hashes and the portable companion payload."""
import hashlib
import json
from pathlib import Path
import tarfile
from version import ROOT, release_version

version = release_version()['version']
dist = ROOT / 'dist'
required = [f'droidpier-companion-{version}.apk',
            f'droidpier-{version}-linux-x86_64.tar.gz',
            f'droidpier-{version}-linux-amd64.deb',
            f'droidpier-{version}-linux-x86_64.rpm',
            f'droidpier-{version}-linux-x86_64.AppImage',
            f'droidpier-{version}-linux-files.cdx.json',
            f'droidpier-{version}-dependency-sources.tar.gz', 'SHA256SUMS']
allowed = set(required) | {'open-dex-agent.jar'}
extra = [p.name for p in dist.iterdir() if p.name not in allowed]
if extra: raise SystemExit('Unexpected release files: ' + ', '.join(extra))
missing = [name for name in required if not (dist / name).is_file()]
if missing: raise SystemExit('Missing required artifacts: ' + ', '.join(missing))
manifest = {}
for line in (dist / 'SHA256SUMS').read_text().splitlines():
    digest, name = line.split('  ', 1)
    file = dist / name
    if not file.resolve().is_relative_to(dist.resolve()): raise SystemExit('Unsafe checksum path')
    if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest() != digest:
        raise SystemExit('Checksum mismatch: ' + name)
    manifest[name] = digest
for name in required:
    if name != 'SHA256SUMS' and name not in manifest: raise SystemExit('Artifact not checksummed: ' + name)
with tarfile.open(dist / f'droidpier-{version}-linux-x86_64.tar.gz') as archive:
    for name in ['droidpier/droidpier', 'droidpier/resources/scrcpy/adb',
                 'droidpier/resources/scrcpy/scrcpy', 'droidpier/resources/ffmpeg/ffmpeg',
                 'droidpier/resources/android/open-dex-agent.jar', 'droidpier/NOTICE']:
        archive.getmember(name)
    data = archive.extractfile('droidpier/resources/android/companion.apk').read()
    if hashlib.sha256(data).hexdigest() != manifest[f'droidpier-companion-{version}.apk']:
        raise SystemExit('Bundled companion differs from standalone APK')
    if any('/.tools/' in member.name or '/archive/' in member.name for member in archive):
        raise SystemExit('Private build inputs in archive')
print('Required assets, checksums and portable companion identity verified.')
print('Manual compatibility, signatures and license acceptance still required.')
