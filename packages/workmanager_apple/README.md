# Local Workmanager Apple implementation

Based on `workmanager_apple 0.9.1+2` from
[Flutter Community Workmanager](https://github.com/fluttercommunity/flutter_workmanager).
The original license is retained. The root `dependency_overrides` selects this
directory; it is not published separately.

The Dart API and generated Pigeon codec remain unchanged and match the pinned
`workmanager_platform_interface 0.9.1+1` and existing Android fork.

Local changes for Issue #82:

- Expiration cancels the headless worker, destroys its Flutter context on the
  main queue, and releases the operation's semaphore even if Dart never replies.
- Late native callbacks cannot complete a cancelled operation a second time.
- BG tasks report the Dart outcome rather than treating every non-cancelled
  operation as successful. Missing callback configuration completes as failure.
- Scheduling retains an existing pending request, preventing repeated app
  launches from moving its earliest execution time further into the future.
- Initial scheduling failures reach Dart, where settings can report failure.

The upstream Dart tests are retained. They test the platform interface and do
**not** compile Swift or verify task expiration, native scheduling or delivery.
Those checks require Xcode and an iPhone; see
`docs/SCHOOL_NOTIFICATIONS_DEVICE_TESTS.md` in the root repository.
