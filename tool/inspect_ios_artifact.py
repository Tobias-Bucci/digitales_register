"""Inspect an app/IPA without executing it. Fail closed on unexpected native APIs."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MAGICS = {
    b'\xcf\xfa\xed\xfe': ('<', 32), b'\xfe\xed\xfa\xcf': ('>', 32),
    b'\xce\xfa\xed\xfe': ('<', 28), b'\xfe\xed\xfa\xce': ('>', 28),
}
FAT_MAGICS = {
    b'\xca\xfe\xba\xbe': ('>', False), b'\xbe\xba\xfe\xca': ('<', False),
    b'\xca\xfe\xba\xbf': ('>', True), b'\xbf\xba\xfe\xca': ('<', True),
}
REFERENCES = {
    'camera': ('UIImagePickerController', 'AVCaptureDevice', 'AVCaptureSession',
               'requestAccessForMediaType'),
    'location': ('CLLocation', 'requestWhenInUseAuthorization',
                 'requestAlwaysAuthorization', 'startUpdatingLocation'),
    'legacy_picker': ('DKCamera', 'DKAsset', 'DKImagePickerController', 'DKPhotoGallery'),
}
PURPOSES = {'camera': 'NSCameraUsageDescription',
            'location': 'NSLocationWhenInUseUsageDescription'}


def linked_libraries(data):
    """Read load commands in thin/fat Mach-O on Windows as well as macOS."""
    magic = data[:4]
    if magic in FAT_MAGICS:
        endian, wide = FAT_MAGICS[magic]
        count = struct.unpack_from(endian + 'I', data, 4)[0]
        entry_size = 32 if wide else 20
        libraries = set()
        for index in range(count):
            pos = 8 + index * entry_size + 8
            offset, size = struct.unpack_from(endian + ('QQ' if wide else 'II'), data, pos)
            if offset + size > len(data):
                raise ValueError('Truncated universal Mach-O slice')
            libraries.update(linked_libraries(data[offset:offset + size]))
        return sorted(libraries)
    endian, offset = MAGICS[magic]
    count, command_bytes = struct.unpack_from(endian + 'II', data, 16)
    end = offset + command_bytes
    if end > len(data):
        raise ValueError('Truncated Mach-O load commands')
    libraries = set()
    for _ in range(count):
        command, size = struct.unpack_from(endian + 'II', data, offset)
        if size < 8 or offset + size > end:
            raise ValueError('Invalid Mach-O load command')
        if command & 0x7fffffff in (12, 24, 31, 32, 35):
            name_offset = struct.unpack_from(endian + 'I', data, offset + 8)[0]
            if not 24 <= name_offset < size:
                raise ValueError('Invalid Mach-O library name')
            libraries.add(data[offset + name_offset:offset + size].split(b'\0')[0].decode())
        offset += size
    return sorted(libraries)


def inspect_entries(entries, read, expected):
    app_plists = [name for name in entries if re.fullmatch(r'Payload/[^/]+\.app/Info.plist', name)]
    if len(app_plists) != 1:
        raise ValueError('Expected exactly one top-level app Info.plist')
    info_path = app_plists[0]
    prefix = info_path[:-len('Info.plist')]
    info = plistlib.loads(read(info_path))
    keys = ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion',
            'CFBundleExecutable', *PURPOSES.values())
    report = {'identity': {key: info.get(key) for key in keys},
              'frameworks': [], 'picker_resource_bundles': [],
              'legacy_resources': [], 'binaries': [], 'errors': []}
    errors = report['errors']
    version, build = expected.split('+')
    for key, value in [('CFBundleIdentifier', 'it.bucci.digitalesregister'),
                       ('CFBundleShortVersionString', version), ('CFBundleVersion', build)]:
        if info.get(key) != value:
            errors.append(f'{key}: expected {value}, got {info.get(key)}')
    for name in entries:
        if not name.startswith(prefix) or name.endswith('/'):
            continue
        if any(term in name for term in REFERENCES['legacy_picker']):
            report['legacy_resources'].append(name)
        if name.endswith('.framework/Info.plist'):
            meta = plistlib.loads(read(name))
            report['frameworks'].append({'path': name, 'id': meta.get('CFBundleIdentifier'),
                                         'version': meta.get('CFBundleShortVersionString')})
        if name.endswith('.bundle/Info.plist') and any(
                term in name for term in ('file_picker', *REFERENCES['legacy_picker'])):
            report['picker_resource_bundles'].append({
                'path': name, 'info': plistlib.loads(read(name))})
        # Only scan executable code, not documentation/assets containing API names.
        data = read(name)
        if data[:4] not in MAGICS and data[:4] not in FAT_MAGICS:
            continue
        references = {group: {term: data.count(term.encode()) for term in terms
                              if term.encode() in data}
                      for group, terms in REFERENCES.items()}
        binary = {'path': name, 'sha256': hashlib.sha256(data).hexdigest(),
                  'libraries': linked_libraries(data), 'references': references}
        report['binaries'].append(binary)
        for group, matches in references.items():
            if matches:
                errors.append(f'{name}: unexpected {group} references: {", ".join(matches)}')
                purpose = PURPOSES.get(group)
                if purpose and not str(info.get(purpose) or '').strip():
                    errors.append(f'{info_path}: missing {purpose} for these SDK references')
    if report['legacy_resources']:
        errors.append('Legacy picker resources still embedded (possible stale SPM/Pods cache)')
    executable = prefix + str(info.get('CFBundleExecutable', ''))
    if not any(binary['path'] == executable for binary in report['binaries']):
        errors.append('Missing or non-Mach-O app executable')
    return report


def inspect_artifact(path, expected):
    if path.is_dir():
        prefix = 'Payload/' + path.name + '/'
        files = {prefix + file.relative_to(path).as_posix(): file
                 for file in path.rglob('*') if file.is_file()}
        return inspect_entries(files, lambda name: files[name].read_bytes(), expected)
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate ZIP entries')
        if any('..' in PurePosixPath(name).parts or name.startswith('/') for name in names):
            raise ValueError('Unsafe ZIP entry')
        report = inspect_entries(names, archive.read, expected)
    report['ipa_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', type=Path, help='Runner.app directory or exported IPA')
    parser.add_argument('--expected-version', help='Defaults to pubspec version; e.g. 1.17.3+50')
    parser.add_argument('--report', type=Path, help='Save full diagnostic JSON')
    args = parser.parse_args()
    expected = args.expected_version or re.search(
        r'^version: (\d+\.\d+\.\d+\+\d+)$',
        (ROOT / 'pubspec.yaml').read_text(encoding='utf-8'), re.M)[1]
    try:
        report = inspect_artifact(args.artifact, expected)
    except (OSError, ValueError, KeyError, struct.error, zipfile.BadZipFile,
            plistlib.InvalidFileException) as error:
        parser.exit(1, f'ERROR: artifact inspection failed: {error}\n')
    print('Artifact:', args.artifact)
    print('Final Info.plist:', json.dumps(report['identity'], ensure_ascii=False))
    for framework in report['frameworks']:
        print('Framework:', framework['path'], framework['id'], framework['version'])
    for bundle in report['picker_resource_bundles']:
        print('Picker resource bundle:', bundle['path'],
              bundle['info'].get('CFBundleIdentifier'))
    for binary in report['binaries']:
        print('Mach-O:', binary['path'], 'SHA256:', binary['sha256'])
        print('  Linked libraries:', ', '.join(binary['libraries']))
        print('  API references:', json.dumps(binary['references']))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    for error in report['errors']:
        print('ERROR:', error)
    if report['errors']:
        return 1
    print('PASS: release identity and native API gate; Apple validation remains separate.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
