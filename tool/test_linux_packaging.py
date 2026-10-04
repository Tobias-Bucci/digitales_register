"""Regression checks for rejecting mixed-architecture and stale Linux bundles."""
import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from package_linux import APP_ID, ROOT, check_bundle


class BundleValidationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.bundle = Path(self.temporary.name)
        for name in ("digitales_register", "lib/libflutter_linux_gtk.so", "lib/libapp.so"):
            path = self.bundle / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(self.elf(62))
        for name in ("data/icudtl.dat", f"share/applications/{APP_ID}.desktop",
                     f"share/metainfo/{APP_ID}.metainfo.xml"):
            path = self.bundle / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        (self.bundle / "data/icon.png").write_bytes((ROOT / "linux/icon.png").read_bytes())
        info = self.bundle / "data/flutter_assets/version.json"
        info.parent.mkdir()
        info.write_text(json.dumps({"version": "1.17.1", "build_number": "45"}))

    @staticmethod
    def elf(machine):
        header = bytearray(20)
        header[:6] = b"\x7fELF\x02\x01"
        struct.pack_into("<H", header, 18, machine)
        return header

    @patch("package_linux.subprocess.run")
    def test_both_native_architectures_are_accepted(self, run):
        run.return_value.returncode = 0
        run.return_value.stdout = "libc.so.6 => /lib/libc.so.6"
        run.return_value.stderr = ""
        for arch, machine in (("x64", 62), ("arm64", 183)):
            for name in ("digitales_register", "lib/libflutter_linux_gtk.so", "lib/libapp.so"):
                (self.bundle / name).write_bytes(self.elf(machine))
            self.assertEqual(len(check_bundle(self.bundle, arch, "1.17.1", "45")), 3)

    @patch("package_linux.subprocess.run")
    def test_one_foreign_plugin_rejects_the_whole_bundle(self, run):
        run.return_value.returncode = 0
        run.return_value.stdout = ""
        (self.bundle / "lib/libapp.so").write_bytes(self.elf(183))
        with self.assertRaisesRegex(ValueError, "Wrong ELF architecture"):
            check_bundle(self.bundle, "x64", "1.17.1", "45")

    def test_old_version_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Stale Flutter bundle version"):
            check_bundle(self.bundle, "x64", "1.16.0", "45")

    def test_missing_engine_is_rejected(self):
        (self.bundle / "lib/libflutter_linux_gtk.so").unlink()
        with self.assertRaisesRegex(ValueError, "Missing bundle file"):
            check_bundle(self.bundle, "x64", "1.17.1", "45")

    @patch("package_linux.subprocess.run")
    def test_missing_system_library_is_rejected(self, run):
        run.return_value.returncode = 0
        run.return_value.stdout = "libsecret-1.so.0 => not found"
        run.return_value.stderr = ""
        with self.assertRaisesRegex(ValueError, "Unresolved runtime libraries"):
            check_bundle(self.bundle, "x64", "1.17.1", "45")


if __name__ == "__main__":
    unittest.main()
