#!/usr/bin/env python3
"""Render reviewed public guides for the repository's separate GitHub wiki."""
import argparse
from pathlib import Path
import re
from version import ROOT

PAGES = {
    'Home': 'docs/README.md',
    'Getting-started': 'docs/USER_GUIDE.md',
    'Compatibility': 'docs/COMPATIBILITY.md',
    'Privacy': 'docs/PRIVACY.md',
    'Development': 'docs/DEVELOPMENT.md',
    'Architecture': 'docs/ARCHITECTURE.md',
    'Window-manager': 'docs/WINDOW_MANAGER.md',
    'Releasing': 'docs/RELEASING.md',
    'Third-party-software': 'docs/THIRD_PARTY.md',
    'Runtime-provenance': 'docs/RUNTIME_PROVENANCE.md',
    'Roadmap': 'docs/ROADMAP.md',
    'Maintainers': 'docs/MAINTAINERS.md',
    'Contributing': 'CONTRIBUTING.md',
    'Security': 'SECURITY.md',
    'Code-of-conduct': 'CODE_OF_CONDUCT.md',
    'Changelog': 'CHANGELOG.md',
}

def render(destination):
    destination.mkdir(parents=True, exist_ok=True)
    reverse = {str((ROOT / source).resolve()): title for title, source in PAGES.items()}
    for title, source in PAGES.items():
        path = ROOT / source
        def link(match):
            label, target = match.groups()
            if re.match(r'[a-z]+:|#|//', target):
                return match.group(0)
            file, _, anchor = target.partition('#')
            resolved = (path.parent / file).resolve()
            if str(resolved) in reverse:
                url = 'https://github.com/gysosin/droidpier/wiki/' + reverse[str(resolved)]
            else:
                url = 'https://github.com/gysosin/droidpier/blob/main/' + resolved.relative_to(ROOT).as_posix()
            return f'[{label}]({url}' + ('#' + anchor if anchor else '') + ')'
        content = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', link, path.read_text())
        (destination / f'{title}.md').write_text(content)
    (destination / '_Sidebar.md').write_text('\n'.join(f'* [[{title.replace("-", " ")}|{title}]]' for title in PAGES) + '\n')
    (destination / '_Footer.md').write_text('[DroidPier source and downloads](https://github.com/gysosin/droidpier) · Your Android. A bigger workspace.\n')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    render(parser.parse_args().output)
