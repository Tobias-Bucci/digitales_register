# iOS release preparation

Checked on 2026-10-02 without starting an application build.

| Setting | Prepared value |
| --- | --- |
| App name | Digitales Register |
| Bundle ID | it.bucci.digitalesregister |
| Version / build | 1.17.0 / 44, sourced from pubspec.yaml through Flutter build variables |
| Deployment target | iOS 15.0; required by the current Firebase pods |
| Devices | iPhone and iPad |
| Signing | Existing team 4838ZPN3B8, automatic signing; account access unverified |
| App icons | Existing register artwork, white opaque background, RGB PNGs in every referenced size including 1024 x 1024 |
| Launch screen | Register logo in light/dark assets at 1x, 2x and 3x; removed obsolete evvolution artwork |
| Permissions | Face ID and photo library purposes in German, English, Italian and Ladin |
| Keychain | Default keychain access groups, as required by flutter_secure_storage; no custom sharing group |

The native file metadata APIs in the vendored plugins now have declarations in
their already bundled privacy manifests: `package_info_plus` uses `C617.1` for
install/update dates from its app directories; `file_picker` uses `C617.1` and
`3B52.1` for metadata in its local copies and user-selected files. These manifests
do not replace App Store Connect's App Privacy questionnaire or the other SDKs'
privacy manifests. No tracking permission, camera, microphone, calendar or push
capability is added. The current app picks profile images from the photo library.

## Repeatable preparation and checks

Run from the repository root with dependencies installed:

```sh
dart run tool/prepare_ios_assets.dart
python3 tool/check_ios_release.py
```

The first command resizes the existing artwork into the native assets; the second
only reads files. Neither builds the app. The default launcher-icon configuration
also removes iOS alpha so later icon regeneration preserves the opaque background.

## Remaining checks on the Mac and in App Store Connect

1. Use a supported stable Flutter SDK and **Xcode 26 or later with iOS 26 SDK or
   later**. This is Apple's upload minimum since April 28, 2026; it is separate
   from the app's iOS 15 deployment target.
2. Run `flutter pub get`, then `cd ios && pod install --repo-update`. The committed
   `Podfile.lock` predates the current Firebase and secure-storage dependencies.
   Regenerate and commit its actual resolved result on macOS; it has deliberately
   not been fabricated on Windows. Verify the plugin and Firebase privacy bundles
   in the resolved Pods. The biometric plugin now permits arm64 simulators.
3. Open `ios/Runner.xcworkspace` and confirm the existing Apple team has access to
   the registered bundle ID and valid signing/provisioning. Configure distribution
   signing through Xcode's Organizer when an archive is eventually requested.
4. Confirm App Store Connect accepts version **1.17.0** and that build **44** has
   not already been uploaded for it. Increase the build number in `pubspec.yaml`
   if already used. The remote App Store record and name reservation were not
   accessible during this repository audit.
5. Optional Analytics/Crashlytics remain disabled because there is no real
   `GoogleService-Info.plist`. If they should ship enabled with consent, complete
   [Firebase setup](IOS_FIREBASE_SETUP.md), add the matching resource to Runner,
   and verify the privacy bootstrap and symbol upload. Core operation fails closed
   when Firebase configuration is absent.
6. When a build is authorized, validate its archive in Xcode and test on iPhone
   and iPad: launch in light/dark mode, login/demo, persistent credentials, Face ID,
   profile photo selection, files, orientations, consent/revocation and links.
   This Windows audit cannot certify native compilation or device behavior.
7. Complete screenshots, review notes/demo access, support/privacy policy URLs,
   age rating, App Privacy and encryption/export answers from the actual release.
   Export compliance is not asserted by a guessed Info.plist flag.

The preparation commit uses `[skip ci]` to honor the request not to start a build
when pushing to main, whose existing workflow otherwise builds Linux on pushes.

Sources: [Apple upload requirements](https://developer.apple.com/news/upcoming-requirements/?id=02032026a),
[Flutter iOS release/versioning](https://docs.flutter.dev/deployment/ios),
[Apple required API reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons),
[Apple app icons](https://developer.apple.com/design/human-interface-guidelines/app-icons).
