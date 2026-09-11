"""Android OTA for trusted master builds; secrets stay inside GitHub Actions.

The readiness request is read-only. Releases are explicit workflow actions;
master pushes patch only an existing active release with the exact pubspec version.
"""
import argparse
import base64
import binascii
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener
from uuid import UUID

from ota import check_configuration, check_defines

ROOT = Path(__file__).resolve().parents[1]
BUILD_SECRETS = (
    'APP_DART_DEFINES', 'ANDROID_KEYSTORE_BASE64',
    'ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD',
)


class SetupError(ValueError):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward a bearer credential to a redirect destination.
        return None


def get_json(url, token, service):
    request = Request(url, headers={
        'Authorization': 'Bearer ' + token,
        'Accept': 'application/json',
        'User-Agent': 'LKGroup-Shorebird-CI',
    })
    try:
        with build_opener(NoRedirect()).open(request, timeout=20) as response:
            return json.load(response)
    except HTTPError as error:
        # Do not log request headers or server response bodies.
        raise SetupError(f'{service} request failed (HTTP {error.code}). Check access and token expiry.') from None
    except (URLError, TimeoutError, OSError, ValueError):
        raise SetupError(f'{service} request failed. Check service connectivity and retry.') from None


def release_list(app_id, token):
    data = get_json(f'https://api.shorebird.dev/api/v1/apps/{app_id}/releases', token, 'Shorebird')
    releases = data.get('releases') if isinstance(data, dict) else None
    if not isinstance(releases, list) or not all(isinstance(x, dict) for x in releases):
        raise SetupError('Unexpected Shorebird releases response; no deployment attempted.')
    return releases


def inspect(action, root=ROOT, env=None, fetch_releases=release_list):
    env = os.environ if env is None else env
    version = check_configuration(root)
    if not re.fullmatch(r'\d+\.\d+\.\d+\+\d+', version):
        raise SetupError('An explicit pubspec release version is required.')
    text = (root / 'shorebird.yaml').read_text(encoding='utf-8-sig')
    app_id = str(UUID(re.search(r'^app_id:\s*[\"\']?([\w-]+)', text, re.M)[1]))
    token = env.get('SHOREBIRD_TOKEN', '').strip()
    if not token:
        raise SetupError('SHOREBIRD_TOKEN is missing from repository Actions secrets.')
    releases = fetch_releases(app_id, token)
    matches = [r for r in releases if r.get('version') == version]
    if len(matches) > 1:
        raise SetupError('Ambiguous Shorebird release version; no deployment attempted.')
    statuses = matches[0].get('platform_statuses', {}) if matches else {}
    if not isinstance(statuses, dict):
        raise SetupError('Unexpected Shorebird platform status; no deployment attempted.')
    status = statuses.get('android', 'missing')
    missing = [name for name in BUILD_SECRETS if not env.get(name, '').strip()]
    reasons = []
    if missing:
        reasons.append('Missing Actions secrets: ' + ', '.join(missing))
    if action == 'release' and status != 'missing':
        reasons.append('This Android version already exists. Use patch for active releases; inspect draft releases manually.')
    if action == 'patch' and status != 'active':
        reasons.append('Create the first Shorebird Android release for this exact version before patching.')
    return {
        'app_id': app_id, 'version': version, 'action': action,
        'authenticated': True, 'android_status': status,
        'missing_secrets': missing, 'reasons': reasons,
        'ready': action != 'check' and not reasons,
    }


def report(result, env=None):
    env = os.environ if env is None else env
    lines = [
        'Shorebird authentication and app access: OK',
        'App ID: ' + result['app_id'],
        'Target version: ' + result['version'],
        'Android release status: ' + result['android_status'],
        'Requested action: ' + result['action'],
        'Deployment ready: ' + str(result['ready']).lower(),
        *result['reasons'],
    ]
    if result['action'] == 'check':
        lines.append('Read-only check completed; nothing was published.')
    print('\n'.join(lines))
    if env.get('GITHUB_STEP_SUMMARY'):
        with open(env['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as stream:
            stream.write('## Shorebird Android\n\n' + '\n'.join('- ' + x for x in lines) + '\n')
    if env.get('GITHUB_OUTPUT'):
        with open(env['GITHUB_OUTPUT'], 'a', encoding='utf-8') as stream:
            stream.write('ready=' + str(result['ready']).lower() + '\n')
            stream.write('version=' + result['version'] + '\n')


def property_value(value):
    # java.util.Properties.load(InputStream) uses ISO-8859-1 and Java escapes.
    out = []
    encoded = value.encode('utf-16-be')
    for byte_index in range(0, len(encoded), 2):
        unit = int.from_bytes(encoded[byte_index:byte_index + 2], 'big')
        character = chr(unit)
        if character in '\\:=#! ':
            out.append('\\' + character)
        elif 33 <= unit <= 126:
            out.append(character)
        else:
            out.append(f'\\u{unit:04x}')
    return ''.join(out)


def prepare(root, directory, env):
    for name in BUILD_SECRETS:
        if not env.get(name, '').strip():
            raise SetupError(f'Missing Actions secret: {name}')
    try:
        defines = json.loads(env['APP_DART_DEFINES'])
    except (TypeError, ValueError):
        raise SetupError('APP_DART_DEFINES must be a JSON object with public runtime configuration.') from None
    allowed = {'SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_ANON_KEY'}
    if not isinstance(defines, dict) or set(defines) - allowed or not all(isinstance(x, str) for x in defines.values()):
        raise SetupError('APP_DART_DEFINES must contain only the public Supabase URL and client key.')
    key = defines.get('SUPABASE_PUBLISHABLE_KEY') or defines.get('SUPABASE_ANON_KEY', '')
    if not (key.startswith('sb_publishable_') or key.count('.') == 2):
        raise SetupError('APP_DART_DEFINES needs a publishable/anon client key.')
    defines_file = directory / 'app-config.json'
    defines_file.write_text(json.dumps(defines), encoding='utf-8')
    defines_file.chmod(0o600)
    try:
        check_defines(defines_file)
    except (ValueError, TypeError, KeyError, binascii.Error):
        raise SetupError('Invalid public runtime configuration. Never use a Supabase server/service_role key.') from None
    try:
        keystore = base64.b64decode(''.join(env['ANDROID_KEYSTORE_BASE64'].split()), validate=True)
    except (ValueError, binascii.Error):
        raise SetupError('ANDROID_KEYSTORE_BASE64 is not valid base64.') from None
    if len(keystore) < 128:
        raise SetupError('ANDROID_KEYSTORE_BASE64 does not contain a usable keystore.')
    keystore_file = directory / 'release.keystore'
    keystore_file.write_bytes(keystore)
    keystore_file.chmod(0o600)
    properties = root / 'android/key.properties'
    if properties.exists():
        raise SetupError('Refusing to overwrite an existing android/key.properties.')
    values = {
        'storeFile': str(keystore_file.resolve()),
        'storePassword': env['ANDROID_KEYSTORE_PASSWORD'],
        'keyAlias': env['ANDROID_KEY_ALIAS'],
        'keyPassword': env['ANDROID_KEY_PASSWORD'],
    }
    # Exclusive creation preserves an owner's existing signing configuration.
    stream = properties.open('x', encoding='ascii')
    try:
        with stream:
            stream.write('\n'.join(k + '=' + property_value(v) for k, v in values.items()) + '\n')
        properties.chmod(0o600)
    except OSError:
        properties.unlink(missing_ok=True)
        raise
    return defines_file, keystore_file, properties


def is_current_master(env):
    if env.get('GITHUB_REF') != 'refs/heads/master':
        raise SetupError('OTA publishing is restricted to master.')
    repository = env.get('GITHUB_REPOSITORY', '')
    if repository != 'lkgroupappmater/lkgroup_app' or not env.get('GH_TOKEN'):
        raise SetupError('Expected repository and its read-only Actions token are required.')
    data = get_json(f'https://api.github.com/repos/{repository}/git/ref/heads/master', env['GH_TOKEN'], 'GitHub')
    return data.get('object', {}).get('sha') == env.get('GITHUB_SHA')


def command(action, version, defines):
    args = ['shorebird', action, 'android']
    if action == 'patch':
        args += ['--release-version', version, '--track', 'stable']
    else:
        # Produces an AAB and a sideloadable APK from the same release.
        args += ['--artifact', 'apk']
    return args + ['--', '--dart-define-from-file=' + str(defines)]


def publish(action, root=ROOT, env=None):
    env = os.environ if env is None else env
    if action == 'check':
        raise SetupError('Read-only checks cannot publish.')
    if not is_current_master(env):
        print('A newer master commit exists; this older build will not publish.')
        return
    result = inspect(action, root, env)
    report(result, env)
    if not result['ready']:
        raise SetupError('Deployment prerequisites are incomplete; no build was published.')
    with tempfile.TemporaryDirectory(prefix='lk-shorebird-', dir=env.get('RUNNER_TEMP')) as temporary:
        properties = None
        try:
            defines, keystore, properties = prepare(root, Path(temporary), env)
            key_check = subprocess.run([
                'keytool', '-list', '-keystore', str(keystore),
                '-storepass:env', 'ANDROID_KEYSTORE_PASSWORD',
                '-alias', env['ANDROID_KEY_ALIAS'],
            ], env=env, capture_output=True)
            if key_check.returncode:
                raise SetupError('Android keystore password/alias validation failed; no release was published.')
            subprocess.run(command(action, result['version'], defines), cwd=root, env=env, check=True)
        finally:
            if properties is not None:
                properties.unlink(missing_ok=True)
    if action == 'release':
        print('Install/distribute this Shorebird-built APK/AAB once before devices can receive patches.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('inspect', 'publish'))
    parser.add_argument('--action', required=True, choices=('check', 'patch', 'release'))
    args = parser.parse_args()
    try:
        if args.mode == 'inspect':
            report(inspect(args.action))
        else:
            publish(args.action)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        # CalledProcessError does not contain credential values in our commands.
        print('::error::' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
