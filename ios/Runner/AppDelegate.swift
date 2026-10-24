import WidgetKit
import UIKit
import Flutter
import FirebaseAnalytics
import UserNotifications
import workmanager_apple
import BackgroundTasks

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
      if let registrar = registry.registrar(forPlugin: "SchoolNotificationLifecycle") {
        registerSchoolNotificationChannel(registrar.messenger())
      }
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
      registerSchoolNotificationChannel(controller.binaryMessenger)
      FlutterMethodChannel(name: "dr/privacy_bootstrap", binaryMessenger: controller.binaryMessenger)
        .setMethodCallHandler { call, result in
          if call.method == "ready" { result(privacyReady) }
          else { result(FlutterMethodNotImplemented) }
        }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
      let identifiers = notifications.filter {
        SchoolNotificationPayload.isPersonalThread($0.request.content.threadIdentifier) ||
        SchoolNotificationPayload.isPersonal($0.request.content.userInfo["payload"])
      }.map { $0.request.identifier }
      UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if SchoolNotificationPayload.isPersonalThread(notification.request.content.threadIdentifier) ||
       SchoolNotificationPayload.isPersonal(notification.request.content.userInfo["payload"]) {
      completionHandler([])
      return
    }
    super.userNotificationCenter(center, willPresent: notification,
      withCompletionHandler: completionHandler)
  }
}

private enum SchoolNotificationPayload {
  static func isPersonalThread(_ identifier: String) -> Bool {
    identifier.range(of: "^school_[a-f0-9]{64}$", options: .regularExpression) != nil
  }
  static func isPersonal(_ payload: Any?) -> Bool {
    guard let raw = payload as? String, let data = raw.data(using: .utf8),
      let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
    let account = value["account"] as? String ?? ""
    return value["v"] as? Int == 1 &&
      account.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil &&
      ["grade", "message"].contains(value["category"] as? String ?? "")
  }
}

private func registerSchoolNotificationChannel(_ messenger: FlutterBinaryMessenger) {
  FlutterMethodChannel(name: "dr/school_notifications", binaryMessenger: messenger)
    .setMethodCallHandler { call, result in
      switch call.method {
      case "isForeground": result(UIApplication.shared.applicationState != .background)
      case "canRequestNotificationPermission":
        UNUserNotificationCenter.current().getNotificationSettings { settings in
          DispatchQueue.main.async { result(settings.authorizationStatus == .notDetermined) }
        }
      case "backgroundRefreshAvailable": result(UIApplication.shared.backgroundRefreshStatus == .available)
      case "diagnostics":
        let refresh = UIApplication.shared.backgroundRefreshStatus == .available
        let powerSave = ProcessInfo.processInfo.isLowPowerModeEnabled
        BGTaskScheduler.shared.getPendingTaskRequests { requests in
          DispatchQueue.main.async {
            result(["backgroundRefreshAvailable": refresh, "powerSaveMode": powerSave,
                    "scheduled": requests.contains { $0.identifier == "it.bucci.digitalesregister.schoolRefresh" }])
          }
        }
      case "openSettings":
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
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
