# iOS release preparation

Checked on 2026-11-25 against `main` on Windows, without a Mac, Xcode or
CocoaPods. Nothing was built for iOS; every statement below comes from reading
the repository files or from `tool/check_ios_release.py`. macOS is out of scope
for this document.

| Setting | Prepared value |
| --- | --- |
| Home screen name | Register (`CFBundleDisplayName` and `CFBundleName`) |
| Bundle ID | it.bucci.digitalesregister; widget extension it.bucci.digitalesregister.PlanningWidgets |
| Version / build | 2.0.0 / 58, sourced from pubspec.yaml through Flutter build variables |
| Deployment target | iOS 15.0 for Runner and PlanningWidgets; required by the current Firebase pods |
| Devices | iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`) |
| Signing | Team J8K4RFDLR7, automatic signing; App Store profiles for Runner and PlanningWidgets (App Group group.it.bucci.digitalesregister.planning) set up 2026-11-27 |
| App icons | Existing register artwork, white opaque background, RGB PNGs in every referenced size including 1024 x 1024 |
| Launch screen | Register logo in light/dark assets at 1x, 2x and 3x; removed obsolete evvolution artwork |
| Permissions | Face ID and photo library purposes in German, English, Italian and Ladin |
| Background | `UIBackgroundModes` `fetch`; `BGTaskSchedulerPermittedIdentifiers` lists `it.bucci.digitalesregister.schoolRefresh`, the task `AppDelegate.swift` registers through workmanager_apple |
| Notifications | Local notifications only (flutter_local_notifications); no push capability and no `aps-environment` entitlement |
| Keychain | Default keychain access groups, as required by flutter_secure_storage; no custom sharing group |
| App group | `group.it.bucci.digitalesregister.planning`, shared by Runner and PlanningWidgets for the planning widget snapshot |
| Firebase defaults | `FirebaseCrashlyticsCollectionEnabled`, `FIREBASE_ANALYTICS_COLLECTION_ENABLED`, `GOOGLE_ANALYTICS_IDFA_COLLECTION_ENABLED` and `GOOGLE_ANALYTICS_DEFAULT_ALLOW_ANALYTICS_STORAGE` are `false` in Info.plist |

The native file metadata APIs in the vendored plugins have declarations in
their bundled privacy manifests: `package_info_plus` uses `C617.1` for
install/update dates from its app directories; `file_picker` uses `C617.1` and
`3B52.1` for metadata in its local copies and user-selected files. These manifests
do not replace App Store Connect's App Privacy questionnaire or the other SDKs'
privacy manifests. No tracking permission, camera, microphone or calendar
capability is added. The current app picks profile images from the photo library.

## App-level privacy manifest

`ios/Runner` has no `PrivacyInfo.xcprivacy`, and none was added. The app's own
native code is `ios/Runner/AppDelegate.swift` and
`ios/PlanningWidgets/PlanningWidgets.swift`. Reviewed on 2026-11-25, they use
`FileManager` (application support and app group container URLs,
`fileExists`, `removeItem`), `Data` reads and atomic writes,
`PropertyListSerialization` on Crashlytics' own `CLSUserDefaults.plist` file,
`URLResourceValues.isExcludedFromBackup`, `JSONSerialization`/`JSONDecoder`,
`ProcessInfo.isLowPowerModeEnabled`, `UIApplication.backgroundRefreshStatus`,
`BGTaskScheduler.getPendingTaskRequests`, `UNUserNotificationCenter`, WidgetKit
and `DateFormatter`. None of these is in Apple's required-reason categories
(file timestamps, system boot time, disk space, active keyboards,
`UserDefaults`): the code neither reads file dates nor calls `UserDefaults`.
Dart code reaches such APIs only through plugins, which bring their own
manifests. This is a source review only; **confirm it in Xcode's privacy report
of the archive** and add an app-level manifest if the report attributes a
required-reason API to Runner or PlanningWidgets.

## Repeatable preparation and checks

Run from the repository root with dependencies installed:

```sh
dart run tool/prepare_ios_assets.dart
flutter test tool/launch_assets/generate_test.dart
python3 tool/check_ios_release.py
```

The first command resizes the existing artwork into the app icons, the second
renders the launch screen images from the launch animation (see
`docs/LAUNCH_ANIMATION.md`); the third only reads files. Neither builds the app. The checker expects the name Register,
and checks the Runner app and the PlanningWidgets extension configurations
(Debug, Release, Profile) for consistent versions, bundle IDs, deployment target
and entitlements; `python3 tool/test_check_ios_release.py` runs it against the
current checkout. The default launcher-icon configuration
also removes iOS alpha so later icon regeneration preserves the opaque background.

On 2026-11-26 the checker passed for version 2.0.0, build 58, and its test
passed (both run on Windows). This covers configuration files only.

## Not yet verified on a Mac

- `pod install`: the committed `ios/Podfile.lock` is stale (see step 2 below).
- Native compilation of Runner, PlanningWidgets and the vendored forks in
  `packages/` (`workmanager_apple`, `biometric_storage`, `file_picker`,
  `package_info_plus`, `flutterfire/*`). CI runs on Ubuntu only and has no iOS
  job.
- Xcode archive, its validation and its privacy report.
- Behaviour on an iPhone and an iPad.

## Remaining checks on the Mac and in App Store Connect

1. Use a supported stable Flutter SDK and **Xcode 26 or later with iOS 26 SDK or
   later**. This is Apple's upload minimum since April 28, 2026; it is separate
   from the app's iOS 15 deployment target.
2. Run `flutter pub get`, then `cd ios && pod install --repo-update`. The committed
   `Podfile.lock` lists none of the Firebase pods, `workmanager_apple` or
   `flutter_local_notifications`, although `AppDelegate.swift` imports
   `FirebaseAnalytics` and `workmanager_apple`. Regenerate and commit its actual
   resolved result on macOS; it has deliberately not been fabricated on Windows.
   Verify the plugin and Firebase privacy bundles in the resolved Pods. The
   biometric plugin permits arm64 simulators.
3. Open `ios/Runner.xcworkspace` and confirm the existing Apple team has access to
   the registered bundle IDs, the app group and valid signing/provisioning.
   Configure distribution signing through Xcode's Organizer when archiving.
4. Confirm App Store Connect accepts version **2.0.0** and that build **58** has
   not already been uploaded for it. Increase the build number in `pubspec.yaml`
   if already used. The remote App Store record was not accessible during this
   repository check.
5. `ios/Runner/GoogleService-Info.plist` is ignored by git, so a fresh checkout
   has none; see [Firebase setup](IOS_FIREBASE_SETUP.md) for supplying it. Without
   it, `resetPrivacySDKDefaults()` in `AppDelegate.swift` reports not ready and
   `lib/analytics_service.dart` refuses to initialise Firebase. With it,
   collection still starts off (Info.plist flags above) and is switched on only
   through the consent choices; verify the privacy bootstrap and symbol upload.
6. Validate the archive in Xcode, check its privacy report (see above), and test
   on iPhone and iPad: launch in light/dark mode, login and demo, persistent
   credentials, Face ID, notifications (permission prompt, delivery, hidden
   personal content), background refresh, planning widgets, profile photo
   selection, files, orientations, consent/revocation and links.
7. Complete screenshots, review notes/demo access, support/privacy policy URLs,
   age rating, App Privacy and encryption/export answers from the actual release.
   Export compliance is not asserted by a guessed Info.plist flag.

Sources: [Apple upload requirements](https://developer.apple.com/news/upcoming-requirements/?id=02032026a),
[Flutter iOS release/versioning](https://docs.flutter.dev/deployment/ios),
[Apple required API reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons),
[Apple app icons](https://developer.apple.com/design/human-interface-guidelines/app-icons).
