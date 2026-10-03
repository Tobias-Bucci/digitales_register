# Analytics / Crashlytics platform check — 2026-10-03

Scope: the recently added Firebase Analytics, product/academic analytics and
Crashlytics integration, its startup path, consent flow and native build setup.
This is not a full functional test of every app feature.

## Windows

- `TelemetryCapabilities` disables Analytics and Crashlytics on Windows.
  Collection, consent, reset, report deletion and diagnostic adapters return
  without initializing Firebase or calling unsupported plugins.
- The product analytics gate stays closed because `sdkReady` is false.
- `flutter build windows --release --no-pub` succeeded. The linker emitted
  LNK4078 for multiple `.voltbl` sections; it did not prevent the build.
- No Windows device/UI session or Firebase delivery test was performed.

## iOS

- `ios/Runner/GoogleService-Info.plist` is absent and the Xcode project has no
  resource entry for it. Analytics and Crashlytics are currently unavailable.
  Android's `google-services.json` does not configure the iOS application.
- The existing native bootstrap returns false when that bundled file is
  absent. Dart checks readiness before initializing Firebase. The consent
  controller catches bootstrap failures and keeps both telemetry gates closed,
  including after opt-in and restart.
- Added regression tests for false readiness, a missing native channel and a
  native platform error. They exercise the real Dart adapter and controller,
  verify no Analytics SDK calls and verify startup/consent complete safely.
- Fixed the Crashlytics upload build phase: optional plist/dSYM paths were
  declared as mandatory Xcode inputs. Xcode can reject missing inputs before
  executing the script's existing file guards. The phase now checks those files
  only inside the script. All Runner configurations already disable script
  sandboxing; retain that setting or restore appropriate inputs when enabling
  sandboxing. The phase has no outputs and runs on every build.
- The checked-in `ios/Podfile.lock` contains no Firebase dependencies and needs
  regeneration with `pod install` on macOS before an iOS build. The Podfile,
  app target and Firebase plugin minimums agree on iOS 15.
- iOS compilation, installation and actual SDK delivery cannot be verified on
  this Windows host. No claim of a completed native iOS test is made.

To enable iOS telemetry later: register the exact iOS bundle ID
`it.bucci.digitalesregister` in the intended Firebase project, add its matching
`GoogleService-Info.plist` to the Runner resources, resolve CocoaPods on macOS,
then build and test fresh launch, opt-in, revocation and restart on iOS.
Keep the existing default-off collection and advertising consent settings.

## Verification

55 targeted tests passed across telemetry capabilities, privacy consent,
product analytics, diagnostics and the three privacy UI suites.
`flutter analyze --no-pub --no-fatal-infos` passed with no issues found.
`git diff --check` passed.

Official setup references:
[Apple Firebase setup](https://firebase.google.com/docs/ios/setup) and
[Flutter Crashlytics setup](https://firebase.google.com/docs/crashlytics/flutter/get-started).
