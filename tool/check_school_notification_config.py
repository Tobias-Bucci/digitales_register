"""Static configuration consistency only; never a native delivery qualification."""
import argparse
import json
import plistlib
import re
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def check(condition, description):
    if not condition:
        raise SystemExit(f"FAIL: {description}")
    print(f"PASS: {description}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--merged-manifest', type=Path,
                        help='Also inspect the manifest produced by an Android build')
    args = parser.parse_args()
    dart = (ROOT / 'lib/school_notification_background.dart').read_text(encoding='utf-8')
    task = re.search(r"const schoolNotificationTask = '([^']+)'", dart)[1]
    with (ROOT / 'ios/Runner/Info.plist').open('rb') as file:
        info = plistlib.load(file)
    check(task in info['BGTaskSchedulerPermittedIdentifiers'], 'Dart task matches permitted Apple identifier')
    check('fetch' in info['UIBackgroundModes'], 'Apple background fetch mode enabled')
    swift = (ROOT / 'ios/Runner/AppDelegate.swift').read_text(encoding='utf-8')
    registration = f'withIdentifier: "{task}"'
    check(registration in swift and swift.index(registration) < swift.index('return super.application(application, didFinishLaunchingWithOptions:'),
          'Apple task registered before launch returns')
    check('WorkmanagerPlugin.setPluginRegistrantCallback' in swift and 'registerSchoolNotificationChannel(registrar.messenger())' in swift,
          'Apple headless plugin/lifecycle registration present (source consistency)')
    # flutter_secure_storage filters iOS Keychain queries by accessibility class.
    # The UI and the worker must both read the shared `login` item across classes.
    desktop = (ROOT / 'lib/desktop.dart').read_text(encoding='utf-8')
    service = (ROOT / 'lib/school_notification_service.dart').read_text(encoding='utf-8')
    check('iOptions: keychainAnyAccessibility' in desktop and 'const SchoolNotificationKeychain()' in service
          and 'KeychainAccessibility.first_unlock_this_device' not in service,
          'UI and worker read the shared iOS login across Keychain classes')
    manifest =ET.parse(ROOT / 'android/app/src/main/AndroidManifest.xml').getroot()
    attribute = '{http://schemas.android.com/apk/res/android}name'
    permissions = {element.get(attribute) for element in manifest.findall('uses-permission')}
    check('android.permission.POST_NOTIFICATIONS' in permissions, 'Android notification permission declared')
    check('android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS' not in permissions,
          'No direct battery exemption permission requested')
    check((ROOT / 'android/app/src/main/res/drawable/ic_school_notification.xml').is_file(),
          'Android notification icon available')
    if args.merged_manifest:
        merged = ET.parse(args.merged_manifest).getroot()
        merged_permissions = {e.get(attribute) for e in merged.findall('uses-permission')}
        for permission in ['INTERNET', 'POST_NOTIFICATIONS', 'ACCESS_NETWORK_STATE',
                           'WAKE_LOCK', 'RECEIVE_BOOT_COMPLETED']:
            check(f'android.permission.{permission}' in merged_permissions,
                  f'Built manifest declares {permission}')
        application = merged.find('application')
        services = {e.get(attribute): e for e in application.findall('service')}
        job = services.get('androidx.work.impl.background.systemjob.SystemJobService')
        check(job is not None and job.get(attribute.replace('name', 'permission')) ==
              'android.permission.BIND_JOB_SERVICE', 'Built manifest includes protected WorkManager JobService')
        receivers = {e.get(attribute): e for e in application.findall('receiver')}
        receiver = receivers.get('androidx.work.impl.background.systemalarm.RescheduleReceiver')
        check(receiver is not None and any(
            action.get(attribute) == 'android.intent.action.BOOT_COMPLETED'
            for action in receiver.findall('intent-filter/action')),
            'Built manifest includes WorkManager reboot rescheduling receiver')
    pubspec = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
    for package in ['workmanager_android', 'workmanager_apple']:
        check(f'path: packages/{package}' in pubspec and (ROOT / 'packages' / package / 'pubspec.yaml').is_file(),
              f'{package} local implementation selected')
    check('workmanager_platform_interface: 0.9.1+1' in pubspec,
          'Platform interface remains pinned to matching native codec')
    catalogs = [json.loads((ROOT / f'assets/locales/{language}.json').read_text(encoding='utf-8'))
                for language in ['de', 'en', 'it', 'lld']]
    keys = {key for key in catalogs[0] if key.startswith('schoolNotifications.')}
    check(all({key for key in catalog if key.startswith('schoolNotifications.')} == keys for catalog in catalogs),
          'All personal notification keys available in four languages')
    print('Static checks passed. Swift compilation, scheduling and device delivery remain separate checks.')


if __name__ == '__main__':
    main()
