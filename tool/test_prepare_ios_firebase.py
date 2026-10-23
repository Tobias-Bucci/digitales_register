"""CI configuration failures must not overwrite an existing Firebase file."""
import base64
from pathlib import Path
import plistlib
import tempfile
import unittest

from ios_firebase import APP_ID, BUNDLE_ID, PROJECT_ID
from prepare_ios_firebase import prepare


class PrepareFirebaseTest(unittest.TestCase):
    def test_ci_install_and_existing_local_configuration(self):
        data = plistlib.dumps({'PROJECT_ID': PROJECT_ID, 'BUNDLE_ID': BUNDLE_ID,
                              'GOOGLE_APP_ID': APP_ID, 'GCM_SENDER_ID': '750743736341',
                              'API_KEY': 'synthetic-test-key'})
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'ios/Runner').mkdir(parents=True)
            path = prepare(root, {'FIREBASE_IOS_PLIST_B64': base64.b64encode(data).decode()})
            self.assertEqual(path.read_bytes(), data)
            self.assertEqual(prepare(root, {}), path)
            self.assertEqual(prepare(root, {'IOS_FIREBASE_PLIST_BASE64': base64.b64encode(data).decode()}), path)

    def test_invalid_input_preserves_existing_file_and_does_not_leak_values(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'ios/Runner').mkdir(parents=True)
            target = root / 'ios/Runner/GoogleService-Info.plist'
            target.write_bytes(b'existing file')
            wrong = plistlib.dumps({'PROJECT_ID': 'private-wrong-value'})
            for encoded in ('', 'invalid!', base64.b64encode(b'private-invalid-plist').decode(),
                            base64.b64encode(wrong).decode()):
                with self.assertRaises(ValueError) as caught:
                    prepare(root, {'FIREBASE_IOS_PLIST_B64': encoded})
                self.assertNotIn('private-', str(caught.exception))
                self.assertEqual(target.read_bytes(), b'existing file')

    def test_missing_input_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'Missing iOS Firebase plist'):
                prepare(Path(directory), {})


if __name__ == '__main__':
    unittest.main()
