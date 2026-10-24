# iOS Firebase and Codemagic setup

Repository review: 2026-10-24. The local Runner plist matches project
`digitales-register-ca085`, bundle ID `it.bucci.digitalesregister` and Firebase
Apple app `1:750743736341:ios:2d070d4633f6f209e57e1c`. The Xcode project includes
it in Runner resources. This does not prove Firebase Console availability or a
successful signed build. The plist is ignored and must be supplied to fresh CI
checkouts. No cloud settings have been changed.

## Codemagic configuration

In the existing Codemagic workflow, provide `FIREBASE_IOS_PLIST_B64` as a
protected environment variable containing the base64-encoded contents of the
real matching `GoogleService-Info.plist`. Never echo the variable or enable shell
tracing around it. Encoding is transport, not encryption. Alternatively, an
existing private CI file step can place the plist at
`ios/Runner/GoogleService-Info.plist` before the release script starts.

The earlier name `IOS_FIREBASE_PLIST_BASE64` is accepted as a fallback. When
both variables exist, `FIREBASE_IOS_PLIST_B64` takes precedence. No duplicate
variable is needed. `FIREBASE_OPTIONS_B64` is not used by this helper.

The existing workflow should invoke `bash tool/build_ios_release.sh`. Its first
configuration steps now run:

```sh
python3 tool/prepare_ios_firebase.py
python3 tool/check_ios_release.py
```

The helper validates before writing and preserves an existing file on invalid
input. Without the variable it validates the existing file without rewriting it.
Both paths require the matching project, sender, bundle and app identifiers and
a nonempty API key. Configuration contents are not printed. No Firebase CLI,
service-account credentials or additional initialization path is needed.

The app uses `Firebase.initializeApp()` after native privacy readiness. Generated
`lib/firebase_options.dart` is currently unused; regenerating or injecting that
file alone cannot configure the native iOS bootstrap. `firebase.json` describes
FlutterFire mappings, not CI file delivery. Its current native output mapping
only covers Android; it is not used by this release script.

No `codemagic.yaml` is versioned. The actual Codemagic workflow, protected
variable, signing and publishing settings remain to be configured or verified
in that service. The local helper does not change them.

## Release gates and remaining verification

- The source check requires the Firebase plist, app name `Register`, iOS 15,
  matching version/identity and Boolean default-off telemetry/privacy flags.
- The release script resolves CocoaPods on macOS and rejects the legacy media
  Pods. The current checked-in lockfile is stale: no Firebase Pods and old
  DKImagePickerController/DKPhotoGallery entries. Resolve and review it on macOS;
  do not hand-edit dependencies or report it as regenerated on Windows.
- Archive and exported IPA inspection require a matching bundled Firebase plist,
  default-off privacy flags and the file_picker/package_info_plus privacy
  manifests; tracking declarations are rejected. These checks do not replace
  Apple's privacy validation or verify every required-reason API declaration.
- The Xcode Crashlytics phase requires Firebase configuration and dSYMs for
  Release/Profile and propagates upload-script failures. A successful script
  invocation still needs Firebase-side verification of readable reports.
- The Podfile keeps `FirebaseAnalytics/Core` without IDFA support. Do not remove
  native startup resets, readiness checks or default-denied advertising signals.

Privacy notice version **5** uses explicit diagnostic, usage and academic
choices without an age question or age authorization gate. New decisions do not
store age. Old versions do not grant permission. Academic telemetry additionally
requires usage consent; Windows/Linux remain excluded. Preserve this behavior.

On a real iOS device, verify fresh install, migration from older decisions,
individual grants, denial, withdrawal/restart, offline reports, native cached
override resets and actual network traffic. Test malformed/missing configuration
in controlled development checks. Confirm Analytics delivery and readable
Crashlytics reports after consent. Keep intentional test crashes out of releases.
Update Apple App Privacy from the actual shipped SDKs and behavior.

## Android and Windows

Android Debug always uses `it.bucci.digitalesregister.debug`, Profile always uses
`it.bucci.digitalesregister.profile`, and normal Release keeps
`it.bucci.digitalesregister`. They install alongside each other with separate
Android app storage, settings and login credentials.

The current Android JSON only contains the production package. Debug and Profile
still build without matching Firebase clients: their Google Services task is
disabled and the native readiness gate prevents Firebase initialization, including
when stale generated resources exist. Analytics and Crashlytics are unavailable
in those development builds; the rest of the app remains functional.

To enable Firebase in a development build, register its exact `.debug` or
`.profile` package and supply the real configuration with that client, either in
`android/app/google-services.json` or in
`android/app/src/<buildType>/google-services.json`. The matching configuration
automatically enables Firebase for that build without changing its package name.
The conditional private release (`.irelease`) still needs its own matching client.
Supply ignored files in Android CI before Gradle runs. Do not invent Firebase app
IDs or reuse a Firebase client with a different Android package name.

Windows intentionally has no Analytics or Crashlytics capability. The registered
Firebase Core plugin and generated Windows options do not enable diagnostics.
No Windows setup or telemetry policy change is required.

See [store checklist](STORE_PRIVACY_CHECKLIST.md),
[Firebase Flutter setup](https://firebase.google.com/docs/flutter/setup) and
[Android configuration matching](https://firebase.google.com/docs/android/google-services-plugin-and-file#how_the_json_config_file_is_processed).
