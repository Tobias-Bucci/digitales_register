# Built-in Kotlin migration — 2026-10-13

## Result

The app builds and starts on the connected Samsung SM-S926B (Android 16 / API 36)
without the warning `Your app uses the following plugins that apply Kotlin Gradle
Plugin (KGP)`. No output filters, warning flags, Flutter SDK patches or pub-cache
patches are used.

## Cause and fix

The app's `android.builtInKotlin=false` selected the legacy fallback in the three
official Firebase Gradle scripts. Flutter also applied KGP to Android modules
without an explicit declaration when built-in Kotlin was disabled.

Flutter 3.47.7's `FlutterPluginUtils.getSubprojectPluginState` detects KGP using
regular expressions over build scripts. Its warning still lists conditional KGP
declarations even if enabling built-in Kotlin makes the fallback unreachable.
Consequently, just changing the flag does not resolve this exact warning.

The pub.dev API and `flutter pub outdated` confirmed the already-installed
versions are current: Core 4.15.0, Analytics 12.6.0, Crashlytics 5.4.0. The project
now selects local copies of these releases under `packages/flutterfire/`. Fresh
official archives were compared against all retained files. Only each package's
Android Gradle script and pubspec differ; all Firebase implementation code is
identical to upstream. See the [patch description](../packages/flutterfire/README.md).

The local Gradle scripts remove legacy KGP application, configure the JVM target
for built-in Kotlin and register Kotlin source directories in `.kotlin` rather
than `.java`. The app enables built-in Kotlin and explicitly targets JVM 17.

The settings-level Kotlin 2.3.21 declaration remains `apply false`. Removing it
caused AGP to select Kotlin 2.2.10, rejected by Flutter's minimum 2.2.20 check. It
provides the compiler classpath without applying Android KGP to any module.
The verification task confirms the actual configured Gradle plugin state.

The app still sets `android.newDsl=false` for Flutter's legacy variant API. This
separate compatibility flag is not required by Android KGP anymore; future AGP 10
requires migration of the remaining legacy DSL/API usage.

## Files changed in this follow-up

- `android/gradle.properties`: enable built-in Kotlin; explain legacy DSL flag.
- `android/settings.gradle`: explain the existing compiler-only version declaration.
- `android/app/build.gradle`: add JVM 17 `kotlin.compilerOptions` configuration.
- `pubspec.yaml`: require Flutter 3.47+ and select the three patched packages.
- `pubspec.lock`: record the three local paths and Flutter SDK minimum.
- `packages/flutterfire/firebase_core/`, `firebase_analytics/`,
  `firebase_crashlytics/`: vendor upstream runtime/platform/test/license files,
  excluding examples and build artifacts; change only `android/build.gradle` and
  `pubspec.yaml` in each package.
- `packages/flutterfire/README.md`: patch provenance and removal criteria.
- `tool/verify_builtin_kotlin.gradle`: reject actual Android KGP application in any
  configured module; require JVM 17 Kotlin compilation in the app/Firebase modules.
- This report and a follow-up link in `firebase_migration_2026-10-13.md`.

All pre-existing uncommitted dependency migration and test changes were retained.
No app UI, business logic, Firebase options or consent policy was changed.

## Versions

No dependency or toolchain version was upgraded in this follow-up:

| Component | Before and after |
| --- | --- |
| Flutter / Dart | 3.47.7 / 3.13.5 |
| Gradle / AGP | 9.6.1 / 9.2.0 |
| Kotlin compiler | 2.3.21 |
| Firebase Core / Analytics / Crashlytics | 4.15.0 / 12.6.0 / 5.4.0 |
| Firebase Android BoM | 34.19.0 |
| Core platform interface | 8.1.1 |

The declared Flutter minimum is now 3.47.0 for the app and the three patched
plugins. Built-in Kotlin replaces legacy Android KGP as the compilation mechanism.

## Verification

Executed:

```powershell
flutter clean
flutter pub get
flutter pub outdated
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter build apk --debug --no-pub
flutter run -d <ANDROID_DEVICE_ID> --debug --no-pub --no-resident
flutter run -d <ANDROID_DEVICE_ID> --debug --no-pub -t lib/main.dart
# From android/:
.\gradlew.bat -I ..\tool\verify_builtin_kotlin.gradle verifyBuiltInKotlin --console=plain
```

- Clean/dependency resolution/outdated: successful.
- Analysis: no issues.
- Tests: 490 passed, one Linux-only test skipped.
- Debug APK: built successfully with the migrated Firebase plugins.
- `flutter run`: installed and launched the real `lib/main.dart` app on the device.
  The final interactive run reached the Dart VM service and rendered the first
  frame without the KGP warning. The activity subsequently closed and the debugger
  connection ended; the device crash buffer contained no entry for the earlier
  regular-app run. No claim of a long-duration runtime test is made.
- Gradle verification: `BUILT_IN_KOTLIN_VERIFIED`; no configured module applies
  Android KGP, and app/Core/Analytics/Crashlytics compile Kotlin for JVM 17.
- Full captured build/run logs contain neither the targeted KGP warning nor its
  `Future versions of Flutter will fail to build` continuation.

A temporary Dart entrypoint outside the repository additionally exercised real
native Firebase channels on the same device. It initialized Core, disabled both
collection switches, denied Analytics consent, checked Analytics support, obtained
a native event acknowledgment and a null app instance ID, wrote a local Crashlytics
log and checked for unsent reports. Output:

```text
BUILT_IN_KOTLIN_SMOKE_OK core=[DEFAULT] analytics=native_ack crashlytics=native_ack collection=disabled unsent=false
```

The smoke check did not enable telemetry or deliberately crash the app. It verifies
native SDK/channel integration, not delivery to the Firebase console. Afterwards
the regular `lib/main.dart` app was built and launched again; the temporary target
is not part of the project.

Remaining messages concern legacy AGP DSL/variant APIs, Gradle 10 deprecations,
Android engine intent flags and skipped startup frames. These are separate from
the removed KGP warning. iOS/macOS/Windows native implementations are retained
unchanged; this follow-up validated Android rather than rebuilding those targets.

## References

- https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers
- https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
- https://developer.android.com/build/migrate-to-built-in-kotlin
- https://developer.android.com/build/releases/agp-9-0-0-release-notes
