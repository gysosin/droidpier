#!/usr/bin/env python3
"""Fail closed until the release's manual and automated acceptance is evidenced."""
import json
from version import ROOT, release_version

record = json.loads((ROOT / 'release/acceptance.json').read_text())
if record['version'] != release_version()['version']:
    raise SystemExit('Acceptance applies to a different version')
checks = record['checks']
if len(checks) < 25:
    raise SystemExit('Incomplete acceptance checklist')
pending = [name for name, value in checks.items()
           if value.get('status') != 'passed' or not value.get('evidence', '').strip()]
if pending:
    raise SystemExit('Release publication blocked by:\n' + '\n'.join(pending))
print('All release acceptance checks have recorded passing evidence.')
