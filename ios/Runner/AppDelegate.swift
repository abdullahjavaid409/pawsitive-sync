import Flutter
import UIKit
import UserNotifications
import WidgetKit
// For setPluginRegistrantCallback (notification actions run in a background isolate).
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // "Snooze 15 min" runs Dart in a background engine without opening the
    // app; that engine needs the plugins (notifications, preferences) too.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // Taps, action buttons and foreground presentation reach the plugin.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let pushRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "PawsitivePush") {
      PushBridge.register(with: pushRegistrar)
    }
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PawsitiveWidgets") else { return }
    let channel = FlutterMethodChannel(name: "pawsitive_sync/widgets", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "update" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let payload = call.arguments as? String,
            let group = Bundle.main.object(forInfoDictionaryKey: "PawsitiveAppGroup") as? String,
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil,
            let defaults = UserDefaults(suiteName: group) else {
        result(FlutterError(code: "widget_group_unavailable", message: "The shared widget container is unavailable.", details: nil))
        return
      }
      defaults.set(payload, forKey: "careSnapshotV1")
      WidgetCenter.shared.reloadTimelines(ofKind: "PawsitiveCare")
      result(nil)
    }
  }
}

/// Remote notifications for household pushes, over `pawsitive_sync/push`.
///
/// Dart → native: `register` answers at once with the token already known
/// (or nil) and asks APNs in the background — it never waits, because a
/// simulator or a phone without network may never get one. No permission
/// prompt: alerts use the permission reminders already asked for; silent
/// pushes need none. `ready` flushes pushes that arrived before Dart was
/// listening (a background launch).
/// Native → Dart: `token` (hex) whenever APNs hands one over (also later or
/// when it changes), `token_error`, and `message` with a push's payload.
final class PushBridge: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var knownToken: String?
  private var dartReady = false
  /// Payloads (and their background completion handlers) waiting for Dart.
  private var pending: [([AnyHashable: Any], ((UIBackgroundFetchResult) -> Void)?)] = []

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "pawsitive_sync/push", binaryMessenger: registrar.messenger())
    let instance = PushBridge(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "register":
      result(knownToken)
      DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
    case "ready":
      dartReady = true
      let queued = pending
      pending.removeAll()
      for (payload, completion) in queued { deliver(payload, completion: completion) }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    knownToken = hex
    channel.invokeMethod("token", arguments: hex)
  }

  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    channel.invokeMethod("token_error", arguments: "apns_unavailable")
  }

  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) -> Bool {
    if dartReady {
      deliver(userInfo, completion: completionHandler)
    } else {
      pending.append((userInfo, completionHandler))
      // iOS gives ~30 s of background time; never hold it if Dart is slow.
      DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
        guard let self = self, !self.dartReady else { return }
        if let index = self.pending.firstIndex(where: { ($0.0 as NSDictionary) == (userInfo as NSDictionary) }) {
          self.pending[index].1?(.noData)
          self.pending[index].1 = nil
        }
      }
    }
    return true
  }

  private func deliver(_ payload: [AnyHashable: Any], completion: ((UIBackgroundFetchResult) -> Void)?) {
    var finished = false
    let finish: (UIBackgroundFetchResult) -> Void = { result in
      guard !finished else { return }
      finished = true
      completion?(result)
    }
    var arguments: [String: Any] = [:]
    for (key, value) in payload { arguments["\(key)"] = value }
    channel.invokeMethod("message", arguments: arguments) { _ in finish(.newData) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 25) { finish(.noData) }
  }
}
