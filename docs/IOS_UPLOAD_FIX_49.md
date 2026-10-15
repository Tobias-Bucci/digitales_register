# iOS upload fix: 1.17.3+49

## Findings and change

The app selects an existing profile picture with `FilePicker.pickFiles(type:
FileType.image, withData: true)` and assessment attachments with the document
picker. The Flutter code and its resolved plugin graph contain no camera capture,
QR scanner or device-location feature. The `image` package processes image data;
it is not a camera plugin.

The vendored `file_picker` compiled both PHPicker and its pre-iOS-14 fallbacks:
`UIImagePickerController` and `DKImagePickerController/PhotoGallery`. The latter
pulls in DKPhotoGallery, SDWebImage and SwiftyGif. DKImagePickerController 4.3.9's
`Sources/DKImageDataManager/Model/DKAsset.swift` declares a `CLLocation` property.
These unused native paths explain the camera and location API references; the
rejected archive itself was not available for binary inspection.

The Podfile now sets `Pod::PICKER_LEGACY_MEDIA = false`. The local file_picker
podspec and Objective-C guards honor this option, excluding the entire legacy
path and its Pods. The option defaults to the previous behavior for other users
of this package. Media selection stays enabled and uses the existing PHPicker
implementation, available on all supported devices (the app requires iOS 15).
Document selection is unchanged. No purpose strings or runtime permission
requests were added: the app has no truthful camera/location purpose to describe.
Existing photo-library and Face ID descriptions remain intact.

Upstream source references:
- [DKImagePickerController 4.3.9 podspec](https://github.com/zhangao0086/DKImagePickerController/blob/4.3.9/DKImagePickerController.podspec)
- [DKAsset location property](https://github.com/zhangao0086/DKImagePickerController/blob/4.3.9/Sources/DKImageDataManager/Model/DKAsset.swift)

## Codemagic and release identity

`pubspec.yaml` specifies **1.17.3+49**. All three Runner configurations use
`FLUTTER_BUILD_NAME` / `FLUTTER_BUILD_NUMBER`; the Info.plist uses those same
variables. The bundle identifier is **it.bucci.digitalesregister** in all three.
Generated.xcconfig is ignored and may contain values from an older local build;
Flutter regenerates it when building with the explicit arguments below.

There is no codemagic.yaml/yml or Codemagic workflow in this checkout. The only
checked-in CI workflow builds Linux. Codemagic's external UI configuration,
environment variables, counters and post-build scripts could not be inspected.
No signing, provisioning or account settings were changed.

On the existing macOS workflow, replace its Flutter iOS build command with:

```sh
bash tool/build_ios_release.sh
```

Keep the existing signing setup before this command and artifact publishing
after it. The script explicitly derives `--build-name=1.17.3` and
`--build-number=49` from pubspec, resolves CocoaPods, rejects lingering DK legacy
Pods, builds the IPA and verifies the archived Runner.app's actual version,
build number and bundle identifier. Do not run another build or a plist/version
mutation after this check. If the UI currently uses additional export options,
preserve those export options in the script's `flutter build ipa` command.

The committed Podfile.lock predates the current Flutter dependencies. It was
not hand-edited on Windows. The macOS `pod install` must regenerate it; do not
use CocoaPods deployment/frozen-lock mode for this first resolution. Review
and commit the actual resolved lockfile from macOS afterwards. Do not restore
cached Pods after dependency resolution.

## Validation limits

Local QA runs on Windows. Native compilation, CocoaPods resolution, the produced
archive, App Store validation and photo selection on a device must be checked
on Codemagic/macOS. The script checks release identity before the workflow can
continue to publishing; only Apple's subsequent validation can confirm that
both ITMS-90683 messages have disappeared.

Local results (2026-10-16):

| Check | Result |
| --- | --- |
| `flutter pub get` | Passed; dependency lock unchanged |
| `flutter analyze` | Passed, no issues |
| `flutter test --reporter expanded` | Passed: 490 tests, 1 skipped |
| `python tool/check_ios_release.py` | Passed; version 1.17.3, build 49, three consistent Runner configurations |
| All iOS `.plist` parsing with Python plistlib | Passed |
| `bash -n tool/build_ios_release.sh` | Passed |
| Conditional Objective-C source inspection | PHPicker/document paths retained; UIImagePicker/DK references excluded with legacy option off; default legacy path retained |
| Artifact checker fixtures | Matching fixture accepted; wrong version, build and bundle ID each rejected |
| `git diff --check` | Passed |
| CocoaPods / Xcode / actual Runner.app | Not available on Windows |

Changed files: `pubspec.yaml`, `ios/Podfile`,
`packages/file_picker/ios/file_picker.podspec`,
`packages/file_picker/ios/file_picker/Package.swift` (preserves the default SPM
legacy behavior; this app uses CocoaPods),
`packages/file_picker/ios/file_picker/Sources/file_picker/FilePickerPlugin.m`,
`packages/file_picker/ios/file_picker/Sources/file_picker/include/file_picker/FilePickerPlugin.h`,
`tool/check_ios_release.py`, `tool/build_ios_release.sh`, and this report.
