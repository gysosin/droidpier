#!/usr/bin/env python3
"""Check the public file set, documentation links, versions and release metadata."""
from pathlib import Path
import re
import subprocess
from version import ROOT, release_version


def main():
    names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT).decode().split('\0')
    errors = []
    source_roots = {'.github', 'android', 'apps', 'docs', 'licenses', 'packages', 'plugins', 'release', 'tool'}
    root_files = {'.gitignore', 'README.md', 'LICENSE', 'NOTICE', 'CHANGELOG.md', 'CODE_OF_CONDUCT.md', 'CONTRIBUTING.md', 'SECURITY.md', 'version.properties'}
    for name in sorted(set(filter(None, names))):
        p = ROOT / name
        if not p.is_file():
            continue
        relative = p.relative_to(ROOT)
        if (relative.parts[0] not in source_roots and name not in root_files) or p.name == 'local.properties' or p.suffix in {'.p12', '.jks', '.keystore', '.pem', '.pcap', '.pcapng'}:
            errors.append(f'Private file in source set: {name}')
        if p.stat().st_size > 12 * 1024 * 1024:
            errors.append(f'Oversized source artifact: {name}')
        try:
            content = p.read_text()
        except (UnicodeError, OSError):
            continue
        if re.search(r'-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----|\bgh[pousr]_[A-Za-z0-9]{30,}', content):
            errors.append(f'Possible credential in {name}')
        if p.suffix == '.md':
            for target in re.findall(r'(?<!!)\[[^\]]*\]\(([^)]+)\)', content):
                if re.match(r'[a-z]+:|#|//', target):
                    continue
                path = target.split('#')[0].split(' "')[0]
                if path and not (p.parent / path).exists():
                    errors.append(f'Broken document link in {name}: {target}')
    v = release_version()
    pubspec = (ROOT / 'apps/desktop/pubspec.yaml').read_text()
    if f"version: {v['version']}+{v['androidVersionCode']}" not in pubspec:
        errors.append('Desktop pubspec disagrees with version.properties')
    if errors:
        raise SystemExit('\n'.join(errors))
    print('Public source file, local documentation link and version checks passed.')

if __name__ == '__main__':
    main()
