import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
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
