import argparse
import base64
import json
from pathlib import Path
import tempfile
import unittest

import ota


class OtaTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'shorebird.yaml').write_text(
            'app_id: 12345678-1234-1234-1234-123456789abc\n', encoding='utf-8')
        (self.root / 'pubspec.yaml').write_text(
            'version: 1.0.1+2\nflutter:\n  assets:\n    - shorebird.yaml\n', encoding='utf-8')
        self.defines = self.root / 'runtime config.json'
        self.defines.write_text(json.dumps({'SUPABASE_URL': 'https://example.supabase.co',
                                           'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_test'}))
        self.args = argparse.Namespace(action='patch', platform='android', defines=self.defines,
                                       release_version='1.0.1+2', track='staging', dry_run=True)

    def test_patch_targets_exact_release_and_preserves_config_path(self):
        command = ota.build_command(self.args, self.root, 'shorebird')
        self.assertEqual(command, ['shorebird', 'patch', 'android', '--release-version',
                                  '1.0.1+2', '--track', 'staging', '--dry-run', '--',
                                  '--dart-define-from-file=' + str(self.defines)])

    def test_missing_registration_and_disabled_updates_fail(self):
        (self.root / 'shorebird.yaml').unlink()
        with self.assertRaises(ValueError):
            ota.build_command(self.args, self.root, 'shorebird')
        (self.root / 'shorebird.yaml').write_text(
            'app_id: 12345678-1234-1234-1234-123456789abc\nauto_update: false\n')
        with self.assertRaises(ValueError):
            ota.build_command(self.args, self.root, 'shorebird')

    def test_wrong_release_and_latest_are_rejected(self):
        for version in ('latest', '1.0.0+1'):
            self.args.release_version = version
            with self.assertRaises(ValueError):
                ota.build_command(self.args, self.root, 'shorebird')

    def test_missing_runtime_configuration_and_server_keys_are_rejected(self):
        payload = base64.urlsafe_b64encode(json.dumps({'role': 'service_role'}).encode()).decode().rstrip('=')
        for key in ('', 'sb_secret_never_embed', 'header.' + payload + '.signature'):
            self.defines.write_text(json.dumps({'SUPABASE_URL': 'https://example.supabase.co',
                                               'SUPABASE_PUBLISHABLE_KEY': key}))
            with self.assertRaises(ValueError):
                ota.build_command(self.args, self.root, 'shorebird')


if __name__ == '__main__':
    unittest.main()
