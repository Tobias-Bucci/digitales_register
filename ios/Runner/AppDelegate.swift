import WidgetKit
import UIKit
import Flutter
import FirebaseAnalytics
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var widgetChannel: FlutterMethodChannel?
  private var widgetDestination: String?

  override func application(_ app: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    if url.scheme == "register-planning", url.host == "homework" {
      widgetDestination = "homework"
      widgetChannel?.invokeMethod("onLaunchDestination", arguments: "homework")
      return true
    }
    return super.application(app, open: url, options: options)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let privacyReady = resetPrivacySDKDefaults()
    UNUserNotificationCenter.current().delegate = self
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "it.bucci.digitalesregister.schoolRefresh",
      frequency: NSNumber(value: 15 * 60))
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let widgets = FlutterMethodChannel(name: "dr/android_widgets", binaryMessenger: controller.binaryMessenger)
      widgetChannel = widgets
      widgets.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "consumeLaunchDestination":
          result(self?.widgetDestination)
          self?.widgetDestination = nil
        case "writePlanningSnapshot":
          do {
            try writePlanningSnapshot(call.arguments as? String)
            result(nil)
          } catch {
            result(FlutterError(code: "widget_storage", message: "Could not save widget data", details: nil))
          }
        case "refreshWidgets":
          WidgetCenter.shared.reloadAllTimelines()
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      }
      FlutterMethodChannel(name: "dr/school_notifications", binaryMessenger: controller.binaryMessenger)
        .setMethodCallHandler { call, result in
          if call.method == "backgroundRefreshAvailable" {
            result(application.backgroundRefreshStatus == .available)
          } else { result(FlutterMethodNotImplemented) }
        }
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
  guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
    return false
  }
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

// Export only the two preparation sections into a protected shared container.
private func writePlanningSnapshot(_ payload: String?) throws {
  guard let directory = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: "group.it.bucci.digitalesregister.planning") else {
    throw NSError(domain: "PlanningWidgets", code: 1)
  }
  var file = directory.appendingPathComponent("planning.json")
  guard let payload = payload, let data = payload.data(using: .utf8),
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
    let meta = root["meta"] as? [String: Any], meta["status"] as? String == "ready" else {
    if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    WidgetCenter.shared.reloadAllTimelines()
    return
  }
  let reduced: [String: Any] = ["planningValidOn": root["planningValidOn"] ?? "",
    "schoolBag": root["schoolBag"] ?? [:], "preparation": root["preparation"] ?? [:]]
  try JSONSerialization.data(withJSONObject: reduced).write(to: file,
    options: [.atomic, .completeFileProtection])
  var attributes = URLResourceValues()
  attributes.isExcludedFromBackup = true
  try file.setResourceValues(attributes)
}
