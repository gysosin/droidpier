#!/usr/bin/env python3
"""Verify the release APK's signing identity and public package metadata."""
import os
from pathlib import Path
import re
import subprocess
import sys
from version import ROOT, release_version


def sdk_tool(name):
    sdk = None
    local = ROOT / 'android/local.properties'
    if local.exists():
        for line in local.read_text().splitlines():
            if line.startswith('sdk.dir='):
                sdk = re.sub(r'\\([:=\\ ])', r'\1', line.split('=', 1)[1])
                break
    sdk = sdk or os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not sdk:
        raise SystemExit('Set ANDROID_HOME to verify the release APK.')
    executable = name + ('.bat' if name == 'apksigner' else '.exe') if os.name == 'nt' else name
    tool = Path(sdk) / 'build-tools/35.0.0' / executable
    if not tool.is_file():
        raise SystemExit('Android build-tools 35.0.0 are required for APK verification.')
    return str(tool)


def verify(apk):
    certificate = subprocess.check_output(
        [sdk_tool('apksigner'), 'verify', '--print-certs', str(apk)], text=True)
    digests = re.findall(r'^Signer #\d+ certificate SHA-256 digest: (\w+)$', certificate, re.M)
    expected = (ROOT / 'release/android-certificate-sha256.txt').read_text().strip()
    if digests != [expected]:
        raise SystemExit('APK signing identity does not match the permanent release certificate.')
    metadata = subprocess.check_output([sdk_tool('aapt'), 'dump', 'badging', str(apk)], text=True)
    version = release_version()
    for required in ["name='io.github.shrey113.openandroiddex.companion'",
                     f"versionCode='{version['androidVersionCode']}'",
                     f"versionName='{version['version']}'", "sdkVersion:'26'",
                     "application-label:'DroidPier Companion'"]:
        if required not in metadata:
            raise SystemExit('APK metadata mismatch: ' + required)
    if 'application-debuggable' in metadata:
        raise SystemExit('Release APK must not be debuggable.')
    manifest = subprocess.check_output(
        [sdk_tool('aapt'), 'dump', 'xmltree', str(apk), 'AndroidManifest.xml'], text=True)
    if 'StreamProbeActivity' in manifest:
        raise SystemExit('A development probe is present in the release manifest.')
    print('APK signature, version, product label and production manifest verified.')


if __name__ == '__main__':
    verify(Path(sys.argv[1]))
