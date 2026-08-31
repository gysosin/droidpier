#!/usr/bin/env python3
"""Read the single release version without importing build dependencies."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def release_version():
    values = dict(line.strip().split('=', 1) for line in
                  (ROOT / 'version.properties').read_text().splitlines()
                  if line.strip() and not line.startswith('#'))
    version = values['version']
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[a-z]+\.\d+)?', version):
        raise ValueError('Invalid release version')
    code = int(values['androidVersionCode'])
    if not 1 <= code <= 2100000000:
        raise ValueError('Invalid Android version code')
    return {'version': version, 'androidVersionCode': code,
            'debian': version.replace('-', '~'),
            'rpmVersion': version.split('-')[0],
            'rpmRelease': '0.' + version.split('-', 1)[1] if '-' in version else '1'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('field', nargs='?', default='version')
    args = parser.parse_args()
    values = release_version()
    print(json.dumps(values) if args.field == 'json' else values[args.field])
