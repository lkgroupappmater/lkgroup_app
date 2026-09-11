import base64
import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import shorebird_ci as ci


class ShorebirdCITest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'android').mkdir()
        (self.root / 'shorebird.yaml').write_text(
            'app_id: b64e00d6-2682-4ff0-8519-c8701ce795af\n', encoding='utf-8')
        (self.root / 'pubspec.yaml').write_text(
            'version: 1.0.1+2\nflutter:\n  assets:\n    - shorebird.yaml\n', encoding='utf-8')
        self.env = {
            'SHOREBIRD_TOKEN': 'test-token-do-not-print',
            'APP_DART_DEFINES': json.dumps({
                'SUPABASE_URL': 'https://example.supabase.co',
                'SUPABASE_PUBLISHABLE_KEY': 'sb_publishable_test-only',
            }),
            'ANDROID_KEYSTORE_BASE64': base64.b64encode(b'test-keystore' * 32).decode(),
            'ANDROID_KEYSTORE_PASSWORD': 'test-password',
            'ANDROID_KEY_ALIAS': 'test-alias',
            'ANDROID_KEY_PASSWORD': 'test-key-password',
        }

    def inspect(self, action='patch', releases=None):
        if releases is None:
            releases = [{'version': '1.0.1+2', 'platform_statuses': {'android': 'active'}}]
        return ci.inspect(action, self.root, self.env, lambda app, token: releases)

    def test_only_exact_active_android_release_can_receive_patch(self):
        self.assertTrue(self.inspect()['ready'])
        for releases in [
            [],
            [{'version': '1.0.1+3', 'platform_statuses': {'android': 'active'}}],
            [{'version': '1.0.1+2', 'platform_statuses': {'android': 'draft'}}],
            [{'version': '1.0.1+2', 'platform_statuses': {'ios': 'active'}}],
        ]:
            with self.subTest(releases=releases):
                self.assertFalse(self.inspect(releases=releases)['ready'])

    def test_first_release_requires_explicit_release_action(self):
        self.assertFalse(self.inspect('patch', [])['ready'])
        self.assertFalse(self.inspect('check', [])['ready'])
        self.assertTrue(self.inspect('release', [])['ready'])
        self.assertFalse(self.inspect('release')['ready'])

    def test_read_only_check_never_publishes(self):
        self.assertFalse(self.inspect('check')['ready'])
        with self.assertRaises(ci.SetupError):
            ci.publish('check', self.root, self.env)

    def test_missing_build_secrets_do_not_prevent_authentication_check(self):
        del self.env['ANDROID_KEYSTORE_BASE64']
        result = self.inspect()
        self.assertTrue(result['authenticated'])
        self.assertFalse(result['ready'])
        self.assertEqual(result['missing_secrets'], ['ANDROID_KEYSTORE_BASE64'])

    def test_missing_token_stops_before_network(self):
        self.env['SHOREBIRD_TOKEN'] = ''
        with self.assertRaises(ci.SetupError):
            ci.inspect('check', self.root, self.env,
                       lambda *_: self.fail('Must not make unauthenticated requests'))

    def test_report_contains_status_but_no_secret_values(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            ci.report(self.inspect(), {})
        for value in self.env.values():
            self.assertNotIn(value, output.getvalue())
        self.assertIn('authentication and app access: OK', output.getvalue())

    def test_existing_signing_file_is_preserved(self):
        original = self.root / 'android/key.properties'
        original.write_text('owner-controlled-signing-file')
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(ci.SetupError):
                ci.prepare(self.root, Path(temporary), self.env)
        self.assertEqual(original.read_text(), 'owner-controlled-signing-file')

    def test_signing_values_are_escaped_and_private_files_restricted(self):
        self.env['ANDROID_KEYSTORE_PASSWORD'] = ' leading\\path=값\n!'
        with tempfile.TemporaryDirectory() as temporary:
            defines, keystore, properties = ci.prepare(self.root, Path(temporary), self.env)
            self.assertEqual(json.loads(defines.read_text()), json.loads(self.env['APP_DART_DEFINES']))
            self.assertEqual(keystore.read_bytes(), b'test-keystore' * 32)
            self.assertIn('storePassword=\\ leading\\\\path\\=\\uac12\\u000a\\!', properties.read_text())
            for file in [defines, keystore, properties]:
                self.assertEqual(file.stat().st_mode & 0o777, 0o600)

    def test_runtime_configuration_rejects_server_secrets(self):
        role = base64.urlsafe_b64encode(json.dumps({'role': 'service_role'}).encode()).decode().rstrip('=')
        for key in ['sb_secret_do-not-embed', 'header.' + role + '.signature']:
            self.env['APP_DART_DEFINES'] = json.dumps({
                'SUPABASE_URL': 'https://example.supabase.co', 'SUPABASE_ANON_KEY': key})
            with tempfile.TemporaryDirectory() as temporary:
                with self.assertRaises(ci.SetupError):
                    ci.prepare(self.root, Path(temporary), self.env)
            self.assertFalse((self.root / 'android/key.properties').exists())

    def test_malformed_config_error_does_not_echo_input(self):
        self.env['APP_DART_DEFINES'] = 'private malformed configuration'
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(ci.SetupError) as raised:
                ci.prepare(self.root, Path(temporary), self.env)
        self.assertNotIn(self.env['APP_DART_DEFINES'], str(raised.exception))

    def test_stale_commit_does_not_build_or_publish(self):
        with patch.object(ci, 'is_current_master', return_value=False), \
                patch.object(ci, 'inspect') as inspect, patch.object(ci.subprocess, 'run') as run:
            with contextlib.redirect_stdout(io.StringIO()):
                ci.publish('patch', self.root, self.env)
            inspect.assert_not_called()
            run.assert_not_called()

    def test_pull_request_cannot_publish(self):
        with self.assertRaises(ci.SetupError):
            ci.is_current_master({'GITHUB_REF': 'refs/pull/1/merge'})

    def test_failed_build_removes_signing_and_temporary_files(self):
        seen_files = []

        def run(args, **kwargs):
            if args[0] == 'keytool':
                return subprocess.CompletedProcess(args, 0)
            defines = Path(args[-1].split('=', 1)[1])
            seen_files.extend([defines, defines.parent / 'release.keystore'])
            raise subprocess.CalledProcessError(1, args)

        with patch.object(ci, 'is_current_master', return_value=True), \
                patch.object(ci, 'inspect', return_value=self.inspect()), \
                patch.object(ci.subprocess, 'run', side_effect=run):
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(subprocess.CalledProcessError):
                ci.publish('patch', self.root, self.env)
        self.assertFalse((self.root / 'android/key.properties').exists())
        self.assertTrue(seen_files)
        self.assertTrue(all(not file.exists() for file in seen_files))

    def test_wrong_keystore_password_never_calls_shorebird(self):
        with patch.object(ci, 'is_current_master', return_value=True), \
                patch.object(ci, 'inspect', return_value=self.inspect()), \
                patch.object(ci.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1)) as run:
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(ci.SetupError):
                ci.publish('patch', self.root, self.env)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args[0][0], 'keytool')
        self.assertFalse((self.root / 'android/key.properties').exists())


if __name__ == '__main__':
    unittest.main()
