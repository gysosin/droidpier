import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class BuildVersionDefinesTest(unittest.TestCase):
    def _captured_flutter_build(self, script_name):
        with tempfile.TemporaryDirectory() as temporary:
            temp = Path(temporary)
            capture = temp / 'flutter-arguments.txt'
            fake_bin = temp / 'bin'
            fake_bin.mkdir()

            fake_flutter = fake_bin / 'flutter'
            fake_flutter.write_text(
                '#!/bin/sh\n'
                'printf "%s\\n" "$*" >> "$DROIDPIER_TEST_CAPTURE"\n'
            )
            fake_flutter.chmod(0o755)

            fake_python = fake_bin / 'python3'
            fake_python.write_text(
                '#!/bin/sh\n'
                'if [ "${1##*/}" = version.py ]; then\n'
                '  if [ "${2:-}" = androidVersionCode ]; then\n'
                '    printf "123\\n"\n'
                '  else\n'
                '    printf "0.1.0-test\\n"\n'
                '  fi\n'
                'fi\n'
            )
            fake_python.chmod(0o755)

            fake_bash = fake_bin / 'bash'
            fake_bash.write_text('#!/bin/sh\nexit 0\n')
            fake_bash.chmod(0o755)

            environment = os.environ.copy()
            environment.update(
                {
                    'DROIDPIER_ANDROID_PAYLOAD_DIR': str(temp),
                    'DROIDPIER_FFMPEG': '/bin/true',
                    'DROIDPIER_TEST_CAPTURE': str(capture),
                    'FLUTTER_BIN': str(fake_flutter),
                    'PATH': f'{fake_bin}:{environment["PATH"]}',
                }
            )
            subprocess.run(
                ['/usr/bin/bash', str(ROOT / 'tool' / script_name)],
                cwd=ROOT,
                env=environment,
                check=True,
            )
            return next(
                line
                for line in capture.read_text().splitlines()
                if line.startswith('build ')
            )

    def _assert_version_defines(self, build_arguments):
        self.assertIn(
            '--dart-define=DROIDPIER_VERSION=0.1.0-test', build_arguments
        )
        self.assertIn('--dart-define=DROIDPIER_BUILD=123', build_arguments)
        self.assertRegex(
            build_arguments,
            r'--dart-define=DROIDPIER_BUILT_AT='
            r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z(?:\s|$)',
        )

    def test_linux_build_stamps_version_build_and_utc_time(self):
        self._assert_version_defines(
            self._captured_flutter_build('build_linux.sh')
        )

    def test_macos_build_stamps_version_build_and_utc_time(self):
        self._assert_version_defines(
            self._captured_flutter_build('build_macos.sh')
        )

    def test_windows_build_stamps_version_build_and_utc_time(self):
        script = (ROOT / 'tool' / 'build_windows.ps1').read_text()

        self.assertIn('$builtAt = [DateTime]::UtcNow.ToString(', script)
        self.assertIn('"yyyy-MM-dd\'T\'HH:mm:ss\'Z\'"', script)
        self.assertIn(
            '[System.Globalization.CultureInfo]::InvariantCulture', script
        )
        self.assertIn('"--dart-define=DROIDPIER_VERSION=$version"', script)
        self.assertIn('"--dart-define=DROIDPIER_BUILD=$code"', script)
        self.assertIn('"--dart-define=DROIDPIER_BUILT_AT=$builtAt"', script)


if __name__ == '__main__':
    unittest.main()
