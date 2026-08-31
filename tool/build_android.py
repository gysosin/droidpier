#!/usr/bin/env python3
"""Build one signed companion payload, loading local secrets without logging them."""
import os
from pathlib import Path
import shutil
import subprocess
from version import ROOT, release_version
from verify_android import verify


def main():
    env = os.environ.copy()
    local = Path.home() / '.local/share/droidpier/signing'
    if not env.get('DROIDPIER_KEYSTORE') and (local / 'release.p12').exists():
        env['DROIDPIER_KEYSTORE'] = str(local / 'release.p12')
        env['DROIDPIER_STORE_PASSWORD'] = (local / 'password').read_text().strip()
    if not env.get('DROIDPIER_KEYSTORE') or not env.get('DROIDPIER_STORE_PASSWORD'):
        raise SystemExit('A release keystore and password are required; see docs/RELEASING.md.')
    gradle = ROOT / 'android' / ('gradlew.bat' if os.name == 'nt' else 'gradlew')
    subprocess.run([str(gradle), '-p', str(ROOT / 'android'), 'agentJar',
                    ':companion:assembleRelease', ':companion:writeDependencyInventory', ':companion:lintDebug', ':companion:lintRelease', 'test', '--no-daemon'], env=env, check=True)
    version = release_version()['version']
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    target = dist / f'droidpier-companion-{version}.apk'
    apk = ROOT / 'android/companion/build/outputs/apk/release/companion-release.apk'
    verify(apk)
    shutil.copy2(apk, target)
    shutil.copy2(ROOT / 'android/agent/build/outputs/open-dex-agent.jar', dist / 'open-dex-agent.jar')
    shutil.copy2(ROOT / 'android/companion/build/outputs/release-dependencies.json', dist / 'android-dependencies.json')
    print(f'Signed companion: {target.name}')


if __name__ == '__main__':
    main()
