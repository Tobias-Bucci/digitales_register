"""The iOS release gate must accept the current checkout's intended identity."""
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CheckIosReleaseTest(unittest.TestCase):
    def test_current_checkout_passes_identity_and_project_checks(self):
        run = subprocess.run([sys.executable, '-B', str(ROOT / 'tool/check_ios_release.py')],
                             capture_output=True, text=True, cwd=ROOT)
        errors = [line for line in run.stdout.splitlines() if line.startswith('ERROR: ')]
        # The Firebase plist is a local/CI secret and may be absent here.
        unrelated = ['ERROR: Missing Runner Firebase plist; run tool/prepare_ios_firebase.py']
        self.assertEqual([e for e in errors if e not in unrelated], [], run.stdout + run.stderr)
        if not errors:
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn('Register; iOS 15+.', run.stdout)


if __name__ == '__main__':
    unittest.main()
