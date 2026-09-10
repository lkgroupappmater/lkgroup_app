"""Prepare/release/patch the app with the official Shorebird CLI (Python 3.9+).

No credentials or app IDs are generated locally. `init` uses the owner's
Shorebird login. Publishing retains Shorebird's interactive confirmation.
"""
import argparse
import base64
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import urlparse
from uuid import UUID

ROOT = Path(__file__).resolve().parents[1]


def check_configuration(root):
    config = root / 'shorebird.yaml'
    if not config.is_file():
        raise ValueError('Run python tool/ota.py init first (Shorebird account required).')
    text = config.read_text(encoding='utf-8-sig')
    match = re.search(r'^app_id:\s*[\"\']?([\w-]+)', text, re.M)
    if not match or UUID(match[1]).int == 0:
        raise ValueError('shorebird.yaml must contain the real app_id from shorebird init.')
    if re.search(r'^auto_update:\s*false\b', text, re.M):
        raise ValueError('auto_update is disabled in shorebird.yaml.')
    pubspec = (root / 'pubspec.yaml').read_text(encoding='utf-8-sig')
    if not re.search(r'^\s+-\s+shorebird\.yaml\s*$', pubspec, re.M):
        raise ValueError('shorebird.yaml must be listed in pubspec.yaml assets.')
    version = re.search(r'^version:\s*(\S+)', pubspec, re.M)
    if not version:
        raise ValueError('pubspec.yaml version is missing.')
    return version[1]


def check_defines(path):
    values = json.loads(path.read_text(encoding='utf-8-sig'))
    url = urlparse(values.get('SUPABASE_URL', ''))
    key = values.get('SUPABASE_PUBLISHABLE_KEY') or values.get('SUPABASE_ANON_KEY', '')
    if url.scheme != 'https' or not url.hostname or not key.strip():
        raise ValueError('Defines must contain SUPABASE_URL and the public Supabase key.')
    if key.startswith('sb_secret_'):
        raise ValueError('Use a publishable/anon key, never a server secret.')
    if key.count('.') == 2:
        part = key.split('.')[1]
        payload = json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))
        if payload.get('role') != 'anon':
            raise ValueError('Only an anon JWT may be embedded in the app.')


def build_command(args, root, executable):
    version = check_configuration(root)
    defines = args.defines.resolve()
    check_defines(defines)
    command = [executable, args.action, args.platform]
    if args.action == 'patch':
        if not re.fullmatch(r'\d+\.\d+\.\d+\+\d+', args.release_version):
            raise ValueError('Use an explicit release version, e.g. 1.0.1+2 (not latest).')
        if args.release_version != version:
            raise ValueError('Check out the source for that release; pubspec version must match.')
        command += ['--release-version', args.release_version, '--track', args.track]
        if args.dry_run:
            command += ['--dry-run']
    elif args.flutter_version:
        command += ['--flutter-version', args.flutter_version]
    # List arguments preserve paths with spaces and avoid shell interpolation.
    return command + ['--', '--dart-define-from-file=' + str(defines)]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('init', help='Log in and register the real Shorebird app once.')
    for action in ('release', 'patch'):
        cmd = sub.add_parser(action)
        cmd.add_argument('--platform', choices=('android', 'ios'), default='android')
        cmd.add_argument('--defines', type=Path, required=True,
                         help='Local JSON with the SAME public runtime config for release and patches.')
        if action == 'release':
            cmd.add_argument('--flutter-version')
        else:
            cmd.add_argument('--release-version', required=True)
            cmd.add_argument('--track', choices=('staging', 'stable'), default='staging')
            cmd.add_argument('--dry-run', action='store_true')
    args = parser.parse_args(argv)
    executable = shutil.which('shorebird')
    if not executable:
        parser.error('Install the official CLI first: https://docs.shorebird.dev/')
    try:
        if args.action == 'init':
            if not (ROOT / 'shorebird.yaml').exists():
                subprocess.run([executable, 'login'], cwd=ROOT, check=True)
                subprocess.run([executable, 'init'], cwd=ROOT, check=True)
            check_configuration(ROOT)
            print('Registered. Commit shorebird.yaml and pubspec.yaml, then create the first release.')
        else:
            command = build_command(args, ROOT, executable)
            subprocess.run(command, cwd=ROOT, check=True)
            if args.action == 'release':
                print('Install/distribute this Shorebird-built release once before sending patches.')
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
