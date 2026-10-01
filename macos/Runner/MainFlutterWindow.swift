import Cocoa
import FlutterMacOS
import FirebaseAnalytics

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let privacyReady = resetPrivacySDKDefaults(macOS: true)
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMethodChannel(name: "dr/privacy_bootstrap", binaryMessenger: flutterViewController.engine.binaryMessenger)
      .setMethodCallHandler { call, result in
        if call.method == "ready" { result(privacyReady) }
        else { result(FlutterMethodNotImplemented) }
      }

    super.awakeFromNib()
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
