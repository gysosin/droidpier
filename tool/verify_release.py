#!/usr/bin/env python3
"""Verify the mandatory acceptance checks for an explicit release channel."""
import argparse
import json
from version import ROOT, release_version

PREVIEW_REQUIRED = {
    'source_privacy_audit', 'fresh_checkout_build', 'analysis_and_tests',
    'android_release_manifest', 'android_screen_visual_review',
    'desktop_screen_visual_review', 'license_and_corresponding_source_audit',
    'off_device_signing_key_recovery', 'android_signed_upgrade_and_debug_conflict',
    'assets_checksums_notices_links',
}


def verify_acceptance(record, version, channel):
    if channel not in {'verified-beta', 'experimental-preview'}:
        raise ValueError('Unknown publication channel')
    if record['version'] != version:
        raise ValueError('Acceptance applies to a different version')
    if record.get('publicationChannel', 'verified-beta') != channel:
        raise ValueError('Publication channel differs from the reviewed acceptance record')
    if channel == 'experimental-preview' and '-' not in version:
        raise ValueError('Experimental previews must use a prerelease version')
    checks = record['checks']
    if len(checks) < 25 or not PREVIEW_REQUIRED.issubset(checks):
        raise ValueError('Incomplete acceptance checklist')
    pending = []
    for name, value in checks.items():
        if value.get('status') not in {'passed', 'pending'}:
            raise ValueError('Failed or unknown acceptance state: ' + name)
        if value['status'] == 'passed' and not value.get('evidence', '').strip():
            raise ValueError('Passing acceptance lacks evidence: ' + name)
        if value['status'] == 'pending':
            pending.append(name)
    blocked = pending if channel == 'verified-beta' else sorted(PREVIEW_REQUIRED.intersection(pending))
    if blocked:
        raise ValueError('Release publication blocked by:\n' + '\n'.join(blocked))
    return pending


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--channel', choices=['verified-beta', 'experimental-preview'], default='verified-beta')
    args = parser.parse_args()
    record = json.loads((ROOT / 'release/acceptance.json').read_text())
    try:
        pending = verify_acceptance(record, release_version()['version'], args.channel)
    except ValueError as error:
        raise SystemExit(str(error)) from error
    print('Required acceptance checks have passing evidence for ' + args.channel + '.')
    if pending:
        print('Untested preview coverage (not passed):\n' + '\n'.join(pending))


if __name__ == '__main__':
    main()
