"""Install an iOS Firebase plist from CI base64, or validate the existing file.

Uses FIREBASE_IOS_PLIST_B64 (legacy: IOS_FIREBASE_PLIST_BASE64).
No network calls, builds or settings changes.
"""
import base64
import binascii
import os
from pathlib import Path
import sys

from ios_firebase import configuration_errors

ROOT = Path(__file__).resolve().parents[1]


def prepare(root=ROOT, environ=None):
    environ = os.environ if environ is None else environ
    target = root / 'ios/Runner/GoogleService-Info.plist'
    encoded = environ.get('FIREBASE_IOS_PLIST_B64')
    if encoded is None:
        encoded = environ.get('IOS_FIREBASE_PLIST_BASE64')
    if encoded is not None:
        try:
            data = base64.b64decode(''.join(encoded.split()), validate=True)
        except (ValueError, binascii.Error):
            raise ValueError('FIREBASE_IOS_PLIST_B64 must contain valid base64') from None
    elif target.is_file():
        data = target.read_bytes()
    else:
        raise ValueError('Missing iOS Firebase plist; provide FIREBASE_IOS_PLIST_B64 in CI')
    errors = configuration_errors(data)
    if errors:
        raise ValueError('; '.join(errors))
    if encoded is not None:
        # Validate before replacing a local file; do not expose its contents.
        target.write_bytes(data)
        if os.name != 'nt':
            target.chmod(0o600)
    return target


if __name__ == '__main__':
    try:
        prepare()
    except (OSError, ValueError) as error:
        sys.exit(f'ERROR: {error}')
    print('PASS: iOS Firebase configuration is ready for Runner.')
