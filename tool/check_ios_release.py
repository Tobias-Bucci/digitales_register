"""Read-only iOS configuration checks. Python 3; no build or external packages."""
import json
from pathlib import Path
import plistlib
import re
import struct
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
errors = []


def check(condition, message):
    if not condition:
        errors.append(message)


def plist(path):
    return plistlib.loads((ROOT / path).read_bytes())


def png(path):
    data = path.read_bytes()
    check(data[:8] == b'\x89PNG\r\n\x1a\n', f'Invalid PNG: {path}')
    return struct.unpack('>II', data[16:24]), data[25], data


pubspec = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
version = re.search(r'^version: (\d+\.\d+\.\d+)\+([1-9]\d*)$', pubspec, re.M)
check(version is not None, 'Version must be major.minor.patch+positive build number')
info = plist('ios/Runner/Info.plist')
check(info['CFBundleDisplayName'] == 'Digitales Register', 'Unexpected display name')
check(info['CFBundleName'] == 'Digitales Register', 'Unexpected bundle name')
check(info['CFBundleShortVersionString'] == '$(FLUTTER_BUILD_NAME)', 'Stale app version source')
check(info['CFBundleVersion'] == '$(FLUTTER_BUILD_NUMBER)', 'Stale build number source')
project = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
for setting, value, count in [
    ('MARKETING_VERSION', '"$(FLUTTER_BUILD_NAME)"', 3),
    ('CURRENT_PROJECT_VERSION', '"$(FLUTTER_BUILD_NUMBER)"', 3),
    ('PRODUCT_BUNDLE_IDENTIFIER', 'it.bucci.digitalesregister', 3),
    ('IPHONEOS_DEPLOYMENT_TARGET', '15.0', 6),
    ('ASSETCATALOG_COMPILER_APPICON_NAME', 'AppIcon', 3),
    ('CODE_SIGN_ENTITLEMENTS', 'Runner/Runner.entitlements', 3),
]:
    check(project.count(f'{setting} = {value};') == count, f'Inconsistent {setting}')
podfile = (ROOT / 'ios/Podfile').read_text(encoding='utf-8')
check("platform :ios, '15.0'" in podfile, 'Podfile minimum iOS mismatch')
check(plist('ios/Flutter/AppFrameworkInfo.plist')['MinimumOSVersion'] == '15.0',
      'Flutter framework minimum iOS mismatch')
check('keychain-access-groups' in plist('ios/Runner/Runner.entitlements'), 'Missing keychain entitlement')
for locale in ['de', 'en', 'it', 'lld']:
    strings = (ROOT / f'ios/Runner/{locale}.lproj/InfoPlist.strings').read_text(encoding='utf-8')
    check(f'{locale}.lproj/InfoPlist.strings' in project, f'Unreferenced locale: {locale}')
    for key in ['NSFaceIDUsageDescription', 'NSPhotoLibraryUsageDescription']:
        check(bool(info.get(key)), f'Missing permission description: {key}')
        check(bool(re.search(rf'"{key}"\s*=\s*"[^"]+";', strings)), f'Missing {locale} {key}')

icon_count = 0
for catalog_path in (ROOT / 'ios/Runner/Assets.xcassets').rglob('Contents.json'):
    catalog = json.loads(catalog_path.read_text(encoding='utf-8'))
    for entry in catalog.get('images', []):
        if 'filename' not in entry:
            continue
        path = catalog_path.parent / entry['filename']
        check(path.is_file(), f'Missing asset: {path}')
        if not path.is_file():
            continue
        dimensions, color_type, data = png(path)
        if catalog_path.parent.name == 'AppIcon.appiconset':
            icon_count += 1
            expected = tuple(round(float(n) * float(entry['scale'][:-1]))
                             for n in entry['size'].split('x'))
            check(dimensions == expected, f'Incorrect icon dimensions: {path.name}')
            check(color_type == 2, f'Icon must be RGB without alpha: {path.name}')
            # Transparency can also be encoded as a PNG tRNS chunk.
            offset = 8
            while offset < len(data):
                length = struct.unpack('>I', data[offset:offset + 4])[0]
                check(data[offset + 4:offset + 8] != b'tRNS', f'Transparent icon: {path.name}')
                offset += length + 12

for path in (ROOT / 'ios').rglob('*.storyboard'):
    ET.parse(path)
for name, reasons in [('package_info_plus', {'C617.1'}), ('file_picker', {'C617.1', '3B52.1'})]:
    manifest_path = f'packages/{name}/ios/{name}/Sources/{name}/PrivacyInfo.xcprivacy'
    manifest = plist(manifest_path)
    entries = manifest['NSPrivacyAccessedAPITypes']
    check(any(e['NSPrivacyAccessedAPIType'] == 'NSPrivacyAccessedAPICategoryFileTimestamp'
              and set(e['NSPrivacyAccessedAPITypeReasons']) == reasons for e in entries),
          f'Missing file metadata declaration: {name}')
    spec = (ROOT / f'packages/{name}/ios/{name}.podspec').read_text(encoding='utf-8')
    check('PrivacyInfo.xcprivacy' in spec, f'Unbundled privacy manifest: {name}')

if errors:
    print('\n'.join(f'ERROR: {error}' for error in errors))
    sys.exit(1)
print(f'PASS: iOS configuration, {icon_count} icon slots, launch assets, permissions and plugin manifests.')
if version:
    print(f'Version {version[1]}, build {version[2]}; Digitales Register; iOS 15+.')
print('Manual: confirm unused build number and signing in App Store Connect; resolve CocoaPods on macOS.')
if not (ROOT / 'ios/Runner/GoogleService-Info.plist').is_file():
    print('Optional Firebase is unconfigured; telemetry stays disabled. See docs/IOS_FIREBASE_SETUP.md.')
print('No build started. Xcode/archive validation and device testing remain unverified.')
