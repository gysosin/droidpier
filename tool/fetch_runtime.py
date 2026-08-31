#!/usr/bin/env python3
"""Fetch only checksum-pinned upstream artifacts. Archives stay outside Git."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import urllib.request
from version import ROOT


def fetch(key, cache=None):
    item = json.loads((ROOT / 'tool/runtime-lock.json').read_text())[key]
    cache = Path(cache or ROOT / '.tools/droidpier-downloads')
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / item['file']
    def valid(path):
        return path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256']
    if not valid(target):
        temporary = target.with_suffix(target.suffix + '.download')
        try:
            request = urllib.request.Request(item['url'], headers={'User-Agent': 'DroidPier-build'})
            with urllib.request.urlopen(request, timeout=60) as response, temporary.open('wb') as output:
                while block := response.read(1024 * 1024):
                    output.write(block)
            if not valid(temporary):
                raise ValueError(f'Checksum mismatch for {key}')
            os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('key')
    parser.add_argument('--cache')
    args = parser.parse_args()
    print(fetch(args.key, args.cache))
