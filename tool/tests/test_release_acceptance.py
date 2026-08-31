import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_release import verify_acceptance


class ReleaseAcceptanceTest(unittest.TestCase):
    def record(self, channel='experimental-preview'):
        path = Path(__file__).resolve().parents[2] / 'release/acceptance.json'
        record = json.loads(path.read_text())
        record['publicationChannel'] = channel
        for value in record['checks'].values():
            value.update(status='passed', evidence='Test evidence')
        return record

    def test_preview_preserves_unperformed_device_test(self):
        record = self.record()
        record['checks']['wireless_pairing'] = {'status': 'pending', 'evidence': ''}
        self.assertEqual(verify_acceptance(record, record['version'], 'experimental-preview'), ['wireless_pairing'])
        self.assertEqual(record['checks']['wireless_pairing']['status'], 'pending')

    def test_verified_beta_cannot_skip_device_test(self):
        record = self.record('verified-beta')
        record['checks']['wireless_pairing']['status'] = 'pending'
        with self.assertRaisesRegex(ValueError, 'wireless_pairing'):
            verify_acceptance(record, record['version'], 'verified-beta')

    def test_preview_cannot_skip_redistribution_or_integrity(self):
        for name in ['license_and_corresponding_source_audit', 'assets_checksums_notices_links', 'source_privacy_audit']:
            with self.subTest(name=name):
                record = self.record()
                record['checks'][name]['status'] = 'pending'
                with self.assertRaisesRegex(ValueError, name):
                    verify_acceptance(record, record['version'], 'experimental-preview')

    def test_preview_cannot_disguise_failed_test_as_untested(self):
        record = self.record()
        record['checks']['wireless_pairing']['status'] = 'failed'
        with self.assertRaisesRegex(ValueError, 'Failed or unknown'):
            verify_acceptance(record, record['version'], 'experimental-preview')

    def test_passing_claim_requires_evidence(self):
        record = self.record()
        record['checks']['wireless_pairing']['evidence'] = ''
        with self.assertRaisesRegex(ValueError, 'lacks evidence'):
            verify_acceptance(record, record['version'], 'experimental-preview')

    def test_channel_cannot_be_switched_without_reviewed_record(self):
        record = self.record('verified-beta')
        with self.assertRaisesRegex(ValueError, 'differs'):
            verify_acceptance(record, record['version'], 'experimental-preview')

    def test_stable_version_cannot_use_preview_exception(self):
        record = self.record()
        record['version'] = '1.0.0'
        with self.assertRaisesRegex(ValueError, 'prerelease'):
            verify_acceptance(record, '1.0.0', 'experimental-preview')


if __name__ == '__main__':
    unittest.main()
