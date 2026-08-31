#!/usr/bin/env python3
"""Record resolved runtime components without machine-local paths or profiles."""
import json
from pathlib import Path
from version import ROOT, release_version


def write_inventory(payload):
    version = release_version()['version']
    graph = json.loads((ROOT / 'apps/desktop/.dart_tool/package_graph.json').read_text())
    packages = {p['name']: p for p in graph['packages']}
    visited = set()
    def visit(name):
        if name in visited: return
        visited.add(name)
        for dep in packages[name].get('dependencies', []): visit(dep)
    for root in graph['roots']: visit(root)
    components = [{'type': 'library', 'name': name, 'version': packages[name]['version'],
                   'purl': f'pkg:pub/{name}@{packages[name]["version"]}'}
                  for name in sorted(visited) if name not in graph['roots']]
    for item in json.loads((payload / 'android-dependencies.json').read_text()):
        components.append({'type': 'library', 'group': item['group'], 'name': item['name'],
                           'version': item['version'],
                           'purl': f'pkg:maven/{item["group"]}/{item["name"]}@{item["version"]}',
                           'hashes': [{'alg': 'SHA-256', 'content': item['sha256']}]})
    lock = json.loads((ROOT / 'tool/runtime-lock.json').read_text())
    for key in ['scrcpy-linux-x64', 'ffmpeg-source', 'sdl-source', 'dav1d-source', 'libusb-source', 'appimage-runtime-linux-x64']:
        item = lock[key]
        components.append({'type': 'file', 'name': key,
                           'hashes': [{'alg': 'SHA-256', 'content': item['sha256']}],
                           'externalReferences': [{'type': 'distribution', 'url': item['url']}]})
    result = {'bomFormat': 'CycloneDX', 'specVersion': '1.5', 'version': 1,
              'metadata': {'component': {'type': 'application', 'name': 'DroidPier', 'version': version}},
              'components': components}
    output = ROOT / 'dist' / f'droidpier-{version}-dependencies.cdx.json'
    output.write_text(json.dumps(result, indent=2)+'\n')
    return output
