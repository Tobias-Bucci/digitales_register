import UIKit
import Flutter
import FirebaseAnalytics
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let privacyReady = resetPrivacySDKDefaults()
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      FlutterMethodChannel(name: "dr/privacy_bootstrap", binaryMessenger: controller.binaryMessenger)
        .setMethodCallHandler { call, result in
          if call.method == "ready" { result(privacyReady) }
          else { result(FlutterMethodNotImplemented) }
        }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// Storage compatibility boundary for Firebase Apple Crashlytics.
// Fail closed if the persisted override cannot be reset; Dart will skip Firebase.
private func resetPrivacySDKDefaults(macOS: Bool = false) -> Bool {
  do {
    let support = try FileManager.default.url(for: .applicationSupportDirectory,
      in: .userDomainMask, appropriateFor: nil, create: true)
    var directory = support
    if macOS, let bundle = Bundle.main.bundleIdentifier {
      directory = directory.appendingPathComponent(bundle)
    }
    let file = directory.appendingPathComponent("com.crashlytics/CLSUserDefaults.plist")
    if FileManager.default.fileExists(atPath: file.path) {
      let data = try Data(contentsOf: file)
      guard var values = try PropertyListSerialization.propertyList(from: data,
        options: [], format: nil) as? [String: Any] else { return false }
      values["com.crashlytics.data_collection"] = 2
      try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        .write(to: file, options: .atomic)
    }
    Analytics.setAnalyticsCollectionEnabled(false)
    return true
  } catch { return false }
}
