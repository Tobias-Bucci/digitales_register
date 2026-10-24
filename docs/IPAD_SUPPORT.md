# Native iPad support

Repository verification for issue #80, 2026-10-23.

The app already enables native iPad distribution. No Flutter upgrade or device
family change is needed:

- Runner's Debug, Profile and Release settings use `TARGETED_DEVICE_FAMILY = "1,2"`.
- `ios/Runner/Info.plist` declares all four iPad orientations and does not require
  full screen, allowing resizable iPad windows.
- The launch storyboard and iPad icon variants, including 76-point and 83.5-point
  icons and the App Store marketing icon, are present.

Navigation adapts to the available window width, with a persistent sidebar from
720 logical pixels and drawer/back navigation below it. Open pages remain mounted
when the window changes size. Grades and messages use a centered content area up to
960 logical pixels wide. Navigation items have square 48-pixel touch targets;
grade average rows grow with text size. The timetable date range wraps between
48-pixel navigation buttons in narrow windows.

## Automated checks

```sh
flutter test test/ui/ipad_layout_test.dart test/ui/sidebar_collapsed_test.dart test/ui/grades/grades_test.dart test/ui/messages/messages_test.dart test/ui/calendar/calendar_test.dart
python tool/check_ios_release.py
```

The iPad widget tests resize open grades, messages and timetable pages through
768x1024, 1024x768, 834x1194, 1194x834, 1024x1366, 1366x1024, 720x1024 and
375x1024 logical pixels. They check navigation state, message expansion, readable
content width, modal placement and closing, and return to the dashboard. Separate
regressions cover initial calendar detail visibility and large grade-average text.

The existing general iOS release checker currently reports two unrelated stale
name expectations: it expects `Digitales Register`, while the native display and
bundle names are `Register`. Its other checks pass, including the icon assets.

## Native release validation still required

Widget tests on Windows cannot verify iOS compilation, signing, device behavior
or App Store acceptance. Follow [iOS release preparation](IOS_RELEASE_READINESS.md)
on macOS, build with `flutter build ipa --release`, and validate the archive in
Xcode. Smoke-test iPad portrait/landscape, Split View and window resizing, touch
navigation, timetable selection, message attachments, dialogs and the keyboard on
a simulator and a physical iPad. Supply the required iPad screenshots in App Store
Connect before distribution.
