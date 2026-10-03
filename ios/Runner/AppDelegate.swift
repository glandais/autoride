import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Before `super`, and synchronously: when iOS relaunches a terminated
    // AutoRide for a significant-change or visit event, the event is delivered
    // only to a CLLocationManager that is already monitoring by the time launch
    // returns, and a background launch gets very little runtime. Re-arming from
    // Dart, after the engine and Riverpod have built, would be too late.
    // See AutoRideBackgroundSession and ledger L-084 / T046.
    //
    // `launchOptions` is deliberately not read: the app adopts scenes
    // (`UIApplicationSceneManifest`), and for a scene app UIKit passes `nil`
    // here on every launch, so `launchOptions?[.location]` was always false and
    // no log could ever say `lr:"location"` (L-115). The launch reason is
    // decided later, from the scenes, when Dart asks for it.
    AutoRideBackgroundSession.shared.bootstrap()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The channel can only be attached once a binary messenger exists, which is
    // strictly after `bootstrap` above. That ordering is the point: staying
    // alive must not depend on Dart being up.
    AutoRideBackgroundSession.shared.register(with: engineBridge.applicationRegistrar.messenger())
  }
}
