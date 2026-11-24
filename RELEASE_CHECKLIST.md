# Release checklist

One release ships the same commit and version on every platform. Work through
"Before every release" once, then each platform you publish, then
"After the release".

## Before every release

- [ ] `main` is green in GitHub Actions (workflow **CI**: format, analyze,
      tests, Android debug build, Linux builds).
- [ ] Locally, if CI cannot be used: `flutter pub get`,
      `dart run build_runner build --delete-conflicting-outputs`,
      `dart format --output=none --set-exit-if-changed lib test tool`,
      `flutter analyze`, `flutter test`.
- [ ] Version in `pubspec.yaml`: `version: X.Y.Z+N`. Android (versionCode),
      iOS/macOS (CFBundleVersion), Windows and Linux take it from there; `N`
      must be higher than in every store.
- [ ] `msix_version` in `pubspec.yaml` is `X.Y.N.0` (the Microsoft Store
      needs the fourth component 0).
- [ ] Release notes written in **de, en, it and lld** (see "Release notes").
- [ ] Privacy texts unchanged, or `currentPrivacyNoticeVersion` raised in
      `lib/privacy_consent.dart` (only when the optional purposes change) and
      the public policy updated at the same time
      (`docs/PRIVACY_IMPLEMENTATION.md`).
- [ ] Store answers still match the code: `docs/STORE_PRIVACY_CHECKLIST.md`,
      `docs/STORE_PRIVACY_POLLS.md`.
- [ ] Tag the release commit `vX.Y.Z` and push the tag.

## Release notes

There is no `fastlane/metadata`; the notes are written once per release and
copied into each place:

- [ ] `linux/digitales_register.metainfo.xml`: a new `<release version=…
      date=…>` with an English `<description>` and `xml:lang="de"`, `"it"`
      translations (Flathub shows English by default).
- [ ] The GitHub release (see "After the release").
- [ ] Play Console, App Store Connect and Partner Center: the store's
      "What's new" field per language.

## Android (Google Play)

- [ ] `android/key.properties` points to the upload keystore (never commit
      it). Without it the release build stops; `allowDebugSigningForRelease`
      in `local.properties` is for local tests only and must be off.
- [ ] `android/app/google-services.json` of the production Firebase project
      is present (not in git).
- [ ] Build: `flutter build appbundle --release`. This runs
      `:app:uploadCrashlyticsMappingFileRelease` and uploads the R8 mapping
      and native symbols to Firebase. For a local test build that must not
      talk to Firebase, add `-x :app:uploadCrashlyticsMappingFileRelease`
      to the Gradle call or use `flutter build apk --debug`.
- [ ] Upload the Dart symbols if the build used `--split-debug-info`
      (`firebase crashlytics:symbols:upload`).
- [ ] Smoke test the release APK/AAB on a phone: demo login, a real login,
      consent dialog on first start, a school notification, the home-screen
      widget.
- [ ] Play Console:
  - [ ] Data safety matches `docs/STORE_PRIVACY_CHECKLIST.md` (Firebase
        Analytics adds `BIND_GET_INSTALL_REFERRER_SERVICE`; the AD_ID
        permissions are removed in the manifest).
  - [ ] Target audience and the Families policy: decided by the legal
        review (#156) — users can be under 13.
  - [ ] App access for review: demo login, school empty, `demo` / `demo`.
  - [ ] Release notes in de, en, it (Ladin has no Play locale; it goes into
        the German text if wanted).
  - [ ] Staged rollout, then watch Crashlytics and the pre-launch report.

## iOS and iPadOS (App Store)

Needs a Mac with Xcode; see `docs/IOS_RELEASE_READINESS.md` (it still
describes 1.17.1 and must be brought up to date with the first 2.x build,
#167).

- [ ] `flutter pub get`, then `cd ios && pod install --repo-update`;
      commit the new `ios/Podfile.lock`.
- [ ] `tool/build_ios_release.sh` (runs `tool/prepare_ios_firebase.py` and
      `tool/check_ios_release.py`), or archive in Xcode.
- [ ] Xcode privacy report of the archive: no required-reason API without a
      declaration (the plugins bring their own `PrivacyInfo.xcprivacy`).
- [ ] Upload the dSYMs to Crashlytics (the build phase does it when the
      Firebase plist is present).
- [ ] Test on an iPhone and an iPad: login, demo, consent, school
      notifications, background refresh, Face ID lock.
- [ ] App Store Connect: privacy labels match
      `docs/STORE_PRIVACY_CHECKLIST.md`; export compliance answered in the
      console (`ITSAppUsesNonExemptEncryption` is deliberately not in
      `Info.plist`); review notes with the demo login; release notes in de,
      en, it.

## macOS

- [ ] Same Pods step in `macos/`, `flutter build macos --release`, archive,
      notarize and upload through Xcode.
- [ ] Without a macOS `GoogleService-Info.plist` Firebase stays off; the
      policy names Android and iOS only, so keep it that way unless the
      policy changes (#162).
- [ ] Smoke test: login, saved login survives a restart (Keychain), export.

## Windows (Microsoft Store)

- [ ] `tool/microsoft_store.local.psd1` holds the Partner Center identity
      and publisher (not in git; see `tool/microsoft_store.local.psd1.example`).
- [ ] `flutter build windows --release` and smoke test the build. Note:
      a debug or release run uses the app data of an installed copy.
- [ ] `.\tool\build_windows_store.ps1`, then upload the MSIX from
      `build/windows/msix` in Partner Center with release notes in de, en,
      it.

## Linux (Flathub, .deb, .tar.gz)

See `docs/LINUX_RELEASE_READINESS.md`.

- [ ] `bash tool/build_linux.sh x64` (validates the metainfo and desktop
      file and builds the bundle, `.deb` and `.tar.gz`), then
      `bash tool/smoke_linux.sh x64`. CI builds and smoke-tests x64 and
      arm64 on every push and attaches the packages to a published GitHub
      release.
- [ ] Flathub: set the release commit and the Flutter version in
      `flatpak-flutter.yml`, regenerate with flatpak-flutter
      (`flatpak-flutter.py flatpak-flutter.yml` rewrites
      `io.github.tobias_bucci.digitales_register.yml` and `generated/`),
      check with `flatpak-builder --user --install-deps-from=flathub
      --force-clean --sandbox --repo=repo build-dir
      io.github.tobias_bucci.digitales_register.yml`, commit the generated
      files and copy them to the Flathub repository.
- [ ] On a real GNOME and KDE desktop: a saved login survives a restart
      inside the Flatpak (Secret portal).

## Web

See `docs/WEB_APP.md`.

- [ ] `flutter build web --release --no-web-resources-cdn`.
- [ ] Deploy with the hashed `/static/` layout described there; the school
      proxy (Cloudflare Worker) must be up.
- [ ] Open `/demo` and a real school sign-in in a browser.

## After the release

- [ ] Publish the GitHub release for the tag with the English notes; CI
      then attaches the Linux packages.
- [ ] Check Crashlytics and the store consoles during the first days.
- [ ] Close the issues the release fixes.
