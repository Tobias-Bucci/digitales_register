# FlutterFire: Built-in Kotlin patch

These local packages are based on the official pub.dev archives downloaded on
2026-10-13:

| Package | Upstream version |
| --- | --- |
| firebase_core | 4.15.0 |
| firebase_analytics | 12.6.0 |
| firebase_crashlytics | 5.4.0 |

The root `dependency_overrides` selects these copies. All upstream runtime source,
tests, licenses and platform files are retained. Example applications and generated
build/cache files are excluded. Comparing the retained files with freshly
downloaded archives, ignoring CRLF/LF differences, identifies exactly two modified
files per package:

1. `android/build.gradle`:
   - Remove the conditional legacy Android KGP application entirely.
   - Apply `kotlin.compilerOptions.jvmTarget` unconditionally for built-in Kotlin.
   - Register Kotlin source folders in `android.sourceSets.*.kotlin`, instead of
     `.java`, as required by AGP's built-in Kotlin integration.
2. `pubspec.yaml`:
   - Require Flutter 3.47+, which supports enabling built-in Kotlin in apps.
   - Remove `resolution: workspace`; these are standalone local packages, outside
     FlutterFire's upstream workspace.

No Firebase Dart, Java/Kotlin, Swift, Objective-C or C++ implementation changed.
Package versions and dependency constraints remain upstream versions.

## Why the copies are necessary

The published versions support built-in Kotlin conditionally, but still contain
`apply plugin: 'kotlin-android'` in the fallback branch. Flutter 3.47.7's
`FlutterPluginUtils.getSubprojectPluginState` scans build scripts via regular
expressions. Its warning is based on the declaration, even when that branch is not
executed. The local copies permanently remove legacy KGP support rather than
obscuring the declaration or changing Flutter's warning/logging code.

The app enables `android.builtInKotlin=true`. The settings-level Kotlin 2.3.21
declaration uses `apply false` solely to supply AGP's Kotlin compiler classpath.
AGP's default 2.2.10 fails Flutter 3.47's minimum-version validation. A declaration
does not apply Android KGP; the verification below checks every configured module.
Gradle 9.6.1, AGP 9.2.0, Kotlin 2.3.21 and Firebase BoM 34.19.0 are unchanged.

`android.newDsl=false` remains required for Flutter's existing legacy variant API
integration. Migrating this separate API is outside the Kotlin change.

## Verification

From `android/`:

```powershell
.\gradlew.bat -I ..\tool\verify_builtin_kotlin.gradle verifyBuiltInKotlin --console=plain
```

The check rejects Android KGP in any configured project and verifies JVM 17 Kotlin
debug compilation for the app and all three Firebase plugins.

The app also passes analysis, 490 tests (one Linux-only skip), debug APK compilation
and `flutter run` on a physical Android device without the KGP warning. See
`docs/builtin_kotlin_migration_2026-10-13.md` at the repository root for details.

## Updating or removing the patch

Compare future official releases against these files before updating. Preserve the
source-set and compiler configuration until upstream releases remove the legacy
KGP application, or a future Flutter detector correctly handles conditional
declarations. Then remove all three path overrides, resolve dependencies and run
the Gradle verification, analysis, tests, APK build and Android runtime check.
Never patch the shared pub cache or the installed Flutter SDK.

References:

- https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers
- https://developer.android.com/build/migrate-to-built-in-kotlin
- https://developer.android.com/build/releases/agp-9-0-0-release-notes
