"""Synthetic Mach-O fixtures for the release gate; no iOS build is simulated."""
import plistlib
import struct
import unittest

from inspect_ios_artifact import inspect_entries, linked_libraries


def macho(payload=b'', library=None):
    command = b''
    if library:
        name = library.encode() + b'\0'
        size = (24 + len(name) + 7) // 8 * 8
        command = struct.pack('<6I', 12, size, 24, 0, 0, 0) + name
        command = command.ljust(size, b'\0')
    return struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2,
                       int(bool(command)), len(command), 0, 0) + command + payload


def app(binary=None, build='50'):
    prefix = 'Payload/Runner.app/'
    files = {
        prefix + 'Info.plist': plistlib.dumps({
            'CFBundleIdentifier': 'it.bucci.digitalesregister',
            'CFBundleShortVersionString': '1.17.3', 'CFBundleVersion': build,
            'CFBundleExecutable': 'Runner',
        }),
        prefix + 'Runner': binary if binary is not None else macho(),
    }
    return files


class ArtifactGateTest(unittest.TestCase):
    def test_clean_app_passes_and_asset_text_is_not_scanned(self):
        files = app()
        files['Payload/Runner.app/assets/document.txt'] = b'CLLocation UIImagePickerController'
        self.assertEqual(inspect_entries(files, files.__getitem__, '1.17.3+50')['errors'], [])

    def test_static_camera_and_location_code_fails_without_framework(self):
        files = app(macho(b'UIImagePickerController\0DKCamera\0CLLocationManager\0'))
        report = inspect_entries(files, files.__getitem__, '1.17.3+50')
        self.assertFalse(report['frameworks'])
        self.assertTrue(any('NSCameraUsageDescription' in error for error in report['errors']))
        self.assertTrue(any('NSLocationWhenInUseUsageDescription' in error for error in report['errors']))

    def test_embedded_framework_is_also_scanned(self):
        files = app()
        files['Payload/Runner.app/Frameworks/SDK.framework/SDK'] = macho(b'AVCaptureDevice')
        report = inspect_entries(files, files.__getitem__, '1.17.3+50')
        self.assertTrue(any('SDK.framework/SDK' in error for error in report['errors']))

    def test_old_build_or_missing_executable_fails(self):
        files = app(build='49')
        self.assertTrue(any('CFBundleVersion' in error for error in
                            inspect_entries(files, files.__getitem__, '1.17.3+50')['errors']))
        del files['Payload/Runner.app/Runner']
        self.assertTrue(any('app executable' in error for error in
                            inspect_entries(files, files.__getitem__, '1.17.3+50')['errors']))

    def test_load_commands_in_thin_and_universal_binary(self):
        library = '/System/Library/Frameworks/CoreLocation.framework/CoreLocation'
        thin = macho(library=library)
        fat = struct.pack('>7I', 0xcafebabe, 1, 0x100000c, 0, 28, len(thin), 0) + thin
        self.assertEqual(linked_libraries(thin), [library])
        self.assertEqual(linked_libraries(fat), [library])

    def test_truncated_load_commands_are_rejected(self):
        with self.assertRaises(ValueError):
            linked_libraries(macho(library='library')[:35])


if __name__ == '__main__':
    unittest.main()
