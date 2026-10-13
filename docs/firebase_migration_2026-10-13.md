# FlutterFire migration — 2026-10-13

Follow-up: the subsequent [Built-in Kotlin migration](builtin_kotlin_migration_2026-10-13.md)
replaces the official hosted Firebase packages with narrowly patched local copies
of the same versions and resolves the KGP warning described below. This report
records the earlier dependency migration and its validation at that time.

Validated with Flutter 3.47.7 stable / Dart 3.13.5 on Windows.
The Git working tree was clean before the migration.

## Dependency diagnosis

The Analytics path override and the root test dependency both required
`firebase_core_platform_interface ^7.1.0`. This prevented upgrading to the
requested Firebase releases, which require the 8.x interface. The old API exposes
`FirebasePluginPlatform`; the new one exposes `FirebasePlugin`. Mixing consumers
of those APIs explains the reported missing type / `pluginConstants` errors.

The exact reported compiler errors were not reproduced in this checkout: an
initial `flutter test test/privacy_consent_test.dart` passed after dependency
resolution, and baseline analysis was clean. The migration removes the constraints
that prevented a consistent update; it does not rely on modifying the pub cache.

| Resolved dependency | Before | After |
| --- | --- | --- |
| firebase_core | 4.11.0 | 4.15.0 |
| firebase_analytics | 12.4.3 (local override) | 12.6.0 (pub.dev) |
| firebase_crashlytics | 5.2.4 | 5.4.0 |
| firebase_core_platform_interface | 7.1.0 | 8.1.1 |
| firebase_analytics_platform_interface | 6.0.3 | 6.0.7 |
| firebase_analytics_web | 0.6.1+9 | 0.6.1+13 |
| firebase_core_web | 3.9.0 | 3.12.0 |
| firebase_crashlytics_platform_interface | 3.8.24 | 3.9.0 |
| _flutterfire_internals | 1.3.73 | 1.3.77 |
| Android app Firebase BoM | 34.13.0 | 34.19.0 |

Only these nine Dart packages changed in the existing lockfile. Other dependencies
and overrides were preserved. The Android app BoM now matches Core's Android SDK
version, including the app's direct Crashlytics NDK dependency.

## Local package audit and Analytics fork

Reviewed the root manifest, lockfile, overrides and package manifests under
`packages/`. Analytics was the only local package depending on Firebase.
The other local packages do not constrain the Firebase migration.

Compared every Git-tracked file in `packages/firebase_analytics` with the official
pub.dev 12.4.3 archive, normalizing line endings. Only two files differed:

- `pubspec.yaml`: raised the Flutter minimum from 3.27.0 to 3.44.0.
- `android/build.gradle`: removed plugin-local AGP/Kotlin classpath pins and the
  conditional Kotlin plugin/JVM-target configuration.

The fork was introduced in commit `0e721fa` ("many build fixes"). Its Dart,
Android native and Apple native application APIs contain no project-specific
changes. The official 12.6.0 archive removes the obsolete classpath pins too and
retains conditional Kotlin plugin support for `android.builtInKotlin=false`, as
used by this app. Android compilation verified this replacement.

The override is removed. The old source directory is retained as an inactive
reference, with a notice in its README; it is not used by the resolved app.
Upstream release notes: https://pub.dev/packages/firebase_analytics/changelog

`firebase_core_platform_interface` remains a necessary **test-only** dependency:
`test/support/privacy_test_mocks.dart` imports its generated Core host mock API.
Its constraint is now `any`, allowing FlutterFire to select the compatible version;
the app lockfile records 8.1.1. There is no independent major-version pin or override.

Crashlytics 5.4 uses Pigeon channels. Updated the test mock from its legacy
MethodChannel and extended the existing native-adapter test to cover collection
state, custom keys, logging and error submission. App behavior and UI are unchanged.

## Verification and remaining limitations

- `flutter pub get`: successful; existing lockfile updated, not deleted.
- `flutter pub outdated`: successful; Firebase packages are current. Other available
  upgrades were deliberately left outside this migration.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter expanded`: 490 passed, one Linux-only test skipped.
- `flutter build apk --debug --no-pub`: successful; APK at
  `build/app/outputs/flutter-apk/app-debug.apk`.
- `flutter build windows --debug --no-pub`: successful; executable at
  `build/windows/x64/runner/Debug/DigitalesRegister.exe`.

Android still warns about KGP usage because of the existing built-in Kotlin opt-out.
Windows reports Firebase C++ SDK missing PDB warnings (LNK4099) and LNK4078 from
the MSVC runtime. These do not prevent the debug builds.

No Android device/emulator was connected. Native Firebase runtime/network behavior
was not exercised on a device. Core initialization and Analytics/Crashlytics Dart
adapters are covered through mocked host channels. Analytics and Crashlytics remain
disabled on Windows by the existing telemetry capability policy. iOS/macOS builds
require a macOS host and were not run.
