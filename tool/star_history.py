#!/usr/bin/env python3
"""Record daily aggregate repository stars; never request stargazer identities."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import urllib.request


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('--count', type=int, help='Offline chart rendering using an aggregate count')
    args = parser.parse_args()
    if args.count is not None:
        count = args.count
    else:
        headers = {'Accept': 'application/vnd.github+json', 'User-Agent': 'DroidPier-star-history'}
        if os.environ.get('GH_TOKEN'): headers['Authorization'] = 'Bearer ' + os.environ['GH_TOKEN']
        request = urllib.request.Request('https://api.github.com/repos/gysosin/droidpier', headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                count = json.load(response)['stargazers_count']
        except Exception:
            print('Aggregate star count unavailable; previous chart retained.')
            return
    if not isinstance(count, int) or count < 0: raise SystemExit('Invalid aggregate star count')
    args.directory.mkdir(parents=True, exist_ok=True)
    file = args.directory / 'stars.json'
    data = json.loads(file.read_text()) if file.exists() else []
    day = datetime.now(timezone.utc).date().isoformat()
    data = [p for p in data if p['date'] != day] + [{'date': day, 'stars': count}]
    data.sort(key=lambda p: p['date'])
    max_count = max(1, max(p['stars'] for p in data))
    points = ' '.join(f'{50 + i * 700 / max(1, len(data)-1):.1f},{220 - p["stars"] * 150 / max_count:.1f}' for i,p in enumerate(data))
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="800" height="280" viewBox="0 0 800 280" role="img" aria-label="DroidPier daily aggregate star history: {count} stars">
<rect width="800" height="280" rx="12" fill="#101820"/>
<g fill="#edf4fa" font-family="sans-serif"><text x="40" y="38" font-size="22">DroidPier · star history</text><text x="750" y="38" text-anchor="end" font-size="18">{count} stars</text>
<text x="40" y="255" font-size="13">{data[0]['date']}</text><text x="750" y="255" text-anchor="end" font-size="13">{day} UTC</text></g>
<path d="M50 65 V220 H750" stroke="#526370" fill="none"/><polyline points="{points}" stroke="#59b9ff" stroke-width="3" fill="none"/>
<circle cx="{50 if len(data)==1 else 750}" cy="{220-count*150/max_count:.1f}" r="4" fill="#59b9ff"/>
</svg>\n'''
    file.write_text(json.dumps(data, indent=2) + '\n')
    (args.directory / 'star-history.svg').write_text(svg)
    print(f'Updated {day}: {count} aggregate stars')

if __name__ == '__main__': main()
