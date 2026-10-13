#!/usr/bin/env python3
"""Generate ignored local pairing files for a Debug build of ChatDemo."""
import argparse
import json
import pathlib
import secrets
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hostname', help='Mac Bonjour hostname, without .local')
    args = parser.parse_args()
    hostname = args.hostname or subprocess.check_output(
        ['scutil', '--get', 'LocalHostName'], text=True).strip()
    if not hostname or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-' for c in hostname):
        parser.error('Use a valid Bonjour hostname, without .local')
    demo = pathlib.Path(__file__).resolve().parents[1] / 'Examples' / 'ChatDemo'
    token = secrets.token_urlsafe(32)
    token_file = demo / '.device-test-access-token'
    config_file = demo / 'Sources' / 'DeviceTestConfig.json'
    for path, data in [
        (token_file, token + '\n'),
        (config_file, json.dumps({'tokenServerURL': f'http://{hostname}.local:8765/demo/',
                                  'accessToken': token}, indent=2) + '\n'),
    ]:
        # Restrict permissions before writing secret content, including on reruns.
        path.touch(mode=0o600, exist_ok=True)
        path.chmod(0o600)
        path.write_text(data)
    print(f'Device demo configured for {hostname}.local. Pairing files are ignored by Git.')
    print('Regenerate ChatDemo.xcodeproj and rebuild after changing pairing files.')


if __name__ == '__main__':
    main()
