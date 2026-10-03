import CoreLocation
import Flutter
import Foundation
import UIKit

/// The one thing that keeps the iOS process alive, and the only thing that can
/// bring it back from the dead.
///
/// AutoRide's detection pipeline is motion-gated (audit #3): GPS is subscribed
/// only while the rider is moving. That is right for Android, where a
/// foreground service holds the process regardless (L-067), and wrong for iOS,
/// where the location session *is* the reason the OS keeps the process
/// scheduled. Closing the gate therefore removed the only thing keeping
/// AutoRide alive, iOS suspended it 40 s later, and the sensors that were
/// supposed to re-open the gate stopped being delivered — an absorbing state
/// (ledger L-084). "Always" does not fix it; it was granted on that run.
///
/// This class owns a `CLLocationManager` of its own, separate from
/// geolocator's, and splits the two jobs Dart cannot do:
///
///   * **Stay alive.** While the Dart gate is closed, a deliberately coarse
///     session runs (3 km accuracy, 3 km distance filter). It is served from
///     cell and Wi-Fi, costs essentially nothing, and is enough for iOS to keep
///     the process scheduled so the accelerometer keeps arriving and a
///     departure is noticed immediately rather than 500 m later.
///   * **Come back.** Significant-change and visit monitoring stay armed for as
///     long as automatic detection is enabled. They are the only two APIs that
///     relaunch a terminated app, and they survive a reboot (from the first
///     unlock onwards). Neither is exposed by geolocator, which is why this
///     file exists at all.
///
/// The two managers are never delivering at the same time: Dart calls
/// `setKeepAlive(false)` as it opens its own fine-grained subscription. A 3 km
/// fix must never reach the detection pipeline — it would land in
/// `_lastLocation`, the pre-trip buffer and `GpsSpeedEstimator` and poison the
/// start confidence T048 has just made trustworthy. So coarse fixes, visits and
/// significant changes leave this class as *events for the audit log only*,
/// never as positions.
final class AutoRideBackgroundSession: NSObject {
  static let shared = AutoRideBackgroundSession()

  /// Method channel name, shared with `ios_background_session.dart`.
  static let channelName = "dev.glandais.autoride/ios_background"

  /// Survives termination and reboot: it is what a relaunched process reads to
  /// decide whether it should re-arm or tell the system to forget about us.
  private static let armedKey = "autoride.detectionArmed"

  private let manager = CLLocationManager()
  private var channel: FlutterMethodChannel?

  /// True from launch until Dart has asked how the process was launched, so a
  /// resume cannot be mistaken for a relaunch.
  private var launchReasonPending = false

  /// How long `consumeLaunchReason` waits for a scene to come to the
  /// foreground before calling the launch a background one. A user launch
  /// connects its scene within a few hundred milliseconds; a background launch
  /// never does, and has ~10 s of runtime, so 3 s costs it nothing.
  private static let foregroundGrace: TimeInterval = 3

  private var isMonitoring = false
  private var isKeepAliveRunning = false

  /// `Any?` because `CLBackgroundActivitySession` is iOS 17+ and the
  /// deployment target is 15.0.
  private var backgroundActivitySession: Any?

  private override init() {
    super.init()
    manager.delegate = self
    // Never let the OS pause updates: deciding when location stops is exactly
    // what the Dart gate does, and a silent OS pause is not observable from
    // Dart. Same reasoning as `pauseLocationUpdatesAutomatically: false` in
    // `adaptive_location_settings.dart`.
    manager.pausesLocationUpdatesAutomatically = false
    manager.activityType = .fitness
  }

  // MARK: - Launch

  /// Must be called **synchronously** from
  /// `application(_:didFinishLaunchingWithOptions:)`.
  ///
  /// The location event that relaunched the process is only delivered to a
  /// manager that is already monitoring by the time launch returns, and a
  /// background launch gets only a few seconds of runtime. Re-arming later —
  /// from Dart, after Riverpod has built — is too late.
  func bootstrap() {
    launchReasonPending = true

    if UserDefaults.standard.bool(forKey: Self.armedKey) {
      startMonitoring()
      // The gate starts closed on every launch (`startListening` subscribes
      // motion, not location), so idle is the correct initial state and it is
      // also what holds the process up long enough for Dart to boot.
      setKeepAlive(true)
    } else {
      // Detection is off. If the system still has us on file for
      // significant-change or visit monitoring — the stale registration that
      // may be what relaunched us — tell it to stop. Harmless otherwise.
      stopMonitoring()
    }
  }

  // MARK: - Launch reason

  /// Answers once per process with `lr` = `user` | `background`, plus the raw
  /// observations it was decided from (`st` = the application state, `sc` =
  /// the number of connected scenes, `w` = ms spent waiting), so a device run
  /// can check the verdict rather than trust it.
  ///
  /// A scene app gets no `launchOptions` (L-115), so the only reliable signal
  /// is whether a scene ever comes to the foreground: UIKit connects one for a
  /// user launch and none for a launch the system makes in the background.
  /// `background` covers both background reasons this app declares — a
  /// significant-change / visit event (T046) and a `fetch` refresh — and the
  /// `visit` / `coarse` lines around it say which.
  private func consumeLaunchReason(_ result: @escaping FlutterResult) {
    guard launchReasonPending else { return result(nil) }
    launchReasonPending = false

    if hasForegroundScene() {
      return result(launchReason("user", waitedMs: 0))
    }

    let started = Date()
    var observer: NSObjectProtocol?
    var answered = false
    let finish: (String) -> Void = { [weak self] reason in
      guard let self, !answered else { return }
      answered = true
      if let observer { NotificationCenter.default.removeObserver(observer) }
      let waited = Int(Date().timeIntervalSince(started) * 1000)
      result(self.launchReason(reason, waitedMs: waited))
    }
    observer = NotificationCenter.default.addObserver(
      forName: UIScene.willEnterForegroundNotification, object: nil, queue: .main
    ) { _ in finish("user") }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.foregroundGrace) { [weak self] in
      finish(self?.hasForegroundScene() == true ? "user" : "background")
    }
  }

  private func hasForegroundScene() -> Bool {
    UIApplication.shared.connectedScenes.contains {
      $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
    }
  }

  private func launchReason(_ reason: String, waitedMs: Int) -> [String: Any] {
    let state: String
    switch UIApplication.shared.applicationState {
    case .active: state = "active"
    case .inactive: state = "inactive"
    case .background: state = "background"
    @unknown default: state = "unknown"
    }
    return [
      "lr": reason,
      "st": state,
      "sc": UIApplication.shared.connectedScenes.count,
      "w": waitedMs,
    ]
  }

  // MARK: - Dart-facing API

  func arm() {
    UserDefaults.standard.set(true, forKey: Self.armedKey)
    startMonitoring()
  }

  func disarm() {
    UserDefaults.standard.set(false, forKey: Self.armedKey)
    setKeepAlive(false)
    stopMonitoring()
  }

  /// `true` while the Dart GPS gate is closed. The coarse session and the
  /// fine geolocator one are mutually exclusive by construction.
  func setKeepAlive(_ on: Bool) {
    guard on != isKeepAliveRunning else { return }
    isKeepAliveRunning = on

    if on {
      applyBackgroundFlags()
      manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
      manager.distanceFilter = 3000
      manager.startUpdatingLocation()
      holdBackgroundActivitySession()
    } else {
      manager.stopUpdatingLocation()
      // The activity session is *not* released here: geolocator's own session
      // takes over immediately and monitoring is still armed. It is released
      // in `disarm()`, which is the only moment nothing is running.
    }
    emit("keepAlive", ["on": on])
  }

  // MARK: - Monitoring (the relaunch contract)

  private func startMonitoring() {
    guard !isMonitoring else { return }
    isMonitoring = true
    applyBackgroundFlags()

    if CLLocationManager.significantLocationChangeMonitoringAvailable() {
      manager.startMonitoringSignificantLocationChanges()
    }
    manager.startMonitoringVisits()
    emit("arm", nil)
  }

  private func stopMonitoring() {
    isMonitoring = false
    manager.stopMonitoringSignificantLocationChanges()
    manager.stopMonitoringVisits()
    releaseBackgroundActivitySession()
    emit("disarm", nil)
  }

  private func applyBackgroundFlags() {
    // Assigning this without `UIBackgroundModes: location` in Info.plist throws
    // an Objective-C exception. The key is declared; the guard is documentation.
    if !manager.allowsBackgroundLocationUpdates {
      manager.allowsBackgroundLocationUpdates = true
    }
    // Honest with the user, and the only signal visible from outside the app
    // that the session is really running — which is what the device-validation
    // protocol needs to distinguish "suspended" from "idle but alive".
    manager.showsBackgroundLocationIndicator = true
  }

  private func holdBackgroundActivitySession() {
    guard #available(iOS 17.0, *), backgroundActivitySession == nil else { return }
    // The iOS 17 way of stating "this app is doing background location on
    // purpose". It keeps the process alive for as long as it is held.
    backgroundActivitySession = CLBackgroundActivitySession()
  }

  private func releaseBackgroundActivitySession() {
    guard #available(iOS 17.0, *),
      let session = backgroundActivitySession as? CLBackgroundActivitySession
    else { return }
    session.invalidate()
    backgroundActivitySession = nil
  }

  // MARK: - Channel

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(FlutterMethodNotImplemented) }
      switch call.method {
      case "arm":
        self.arm()
        result(nil)
      case "disarm":
        self.disarm()
        result(nil)
      case "setKeepAlive":
        self.setKeepAlive((call.arguments as? [String: Any])?["on"] as? Bool ?? false)
        result(nil)
      case "consumeLaunchReason":
        self.consumeLaunchReason(result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Fire-and-forget towards Dart. Events raised during a background launch,
  /// before the engine has attached, are simply dropped: the `bootstrap` line
  /// Dart writes for itself is what records that launch.
  private func emit(_ action: String, _ extra: [String: Any]?) {
    var arguments: [String: Any] = ["a": action]
    extra?.forEach { arguments[$0.key] = $0.value }
    channel?.invokeMethod("onEvent", arguments: arguments)
  }
}

// MARK: - CLLocationManagerDelegate

extension AutoRideBackgroundSession: CLLocationManagerDelegate {
  /// Coarse and significant-change fixes both arrive here. Neither is forwarded
  /// as a position — see the class comment. Only the count and the accuracy are
  /// journalled, which is enough to tell "the session is alive" from "the
  /// process was suspended".
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let last = locations.last else { return }
    emit("coarse", ["n": locations.count, "ac": last.horizontalAccuracy])
  }

  func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    emit("visit", ["arr": visit.arrivalDate.timeIntervalSince1970,
                   "dep": visit.departureDate.timeIntervalSince1970])
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    emit("err", ["ex": error.localizedDescription])
  }
}
