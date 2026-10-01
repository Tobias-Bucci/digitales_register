# iOS Firebase setup — pending manual work

No `GoogleService-Info.plist` is present for Runner in this checkout. No bundle ID, App Store ID or Firebase options have been invented. Native privacy readiness now returns false without that resource; Dart fails closed and core app operation continues. Telemetry configuration is attempted at most once per process. Actual Xcode compilation cannot be verified on Windows.

1. Read the actual `PRODUCT_BUNDLE_IDENTIFIER` for each intended Runner build configuration in `ios/Runner.xcodeproj/project.pbxproj` / Xcode. Do not replace it with an inferred identifier.
2. Register a Firebase iOS app with that **exact** ID in the intended existing project.
3. Download its real `GoogleService-Info.plist`, integrate it into the Runner target/resources, and verify configuration/build variant matching.
4. Run/review `flutterfire configure` as appropriate; preserve the existing native privacy bootstrap, version-4 controller and default-off settings. Avoid introducing a second initialization path.
5. Check `FIREBASE_ANALYTICS_COLLECTION_ENABLED=false`, `FirebaseCrashlyticsCollectionEnabled=false`, automatic screens/IDFA off, and advertising/storage defaults denied.
6. Verify existing Podfile no-ad-ID Analytics option, CocoaPods resolution, native startup and cached runtime override reset on a real device. Test absent/malformed config, fresh install, v3 migration, under14/unknown, individual grants and withdrawal/restart.
7. Validate existing Crashlytics dSYM phase and symbol upload with the actual Xcode/Firebase configuration. Presence of a script does not prove successful uploads/readable reports.
8. Check device traffic/DebugView/Crashlytics delivery; no intentional test crash in release.
9. Complete Apple App Privacy disclosure from the actual shipped SDK/behavior; no ATT prompt unless a future separate implementation actually meets Apple's tracking definition.

App Store submission, Firebase registration, private console changes and native device verification remain manual. See [Store privacy checklist](STORE_PRIVACY_CHECKLIST.md) and [Firebase Flutter setup](https://firebase.google.com/docs/flutter/setup).
