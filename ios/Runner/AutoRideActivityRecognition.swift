import CoreMotion
import Flutter
import Foundation

/// The motion activity iOS itself recognises — cycling, automotive, walking,
/// running, stationary — forwarded to Dart for the audit log (T055).
///
/// This is the inertial classifier the project has been missing: the motion
/// coprocessor already tells a bicycle from a car or a walk, from the same
/// accelerometer AutoRide reads. On the 2026-10-09 corpus — read through a
/// second app recording it on the same phone — it was the only signal that
/// separated the two town drives and the seven walks History kept as rides.
///
/// **It decides nothing.** Activities leave this class as journal lines only;
/// no detector reads them. Whether they may later confirm, badge or refuse a
/// recording is a decision to be taken on logs that contain them, and the
/// rule that evidence may label but never silently discard (T053) applies.
///
/// Never asks for the permission: `startActivityUpdates` on an undetermined
/// authorisation would raise the Motion & Fitness prompt from wherever the
/// session happens to start, including a background relaunch. The prompt is
/// raised from the settings screen, through permission_handler's `sensors`
/// permission, which on iOS *is* `CMMotionActivityManager` authorisation.
final class AutoRideActivityRecognition: NSObject {
  static let shared = AutoRideActivityRecognition()

  /// Method channel name, shared with `activity_recognition_session.dart`.
  static let channelName = "dev.glandais.autoride/activity"

  private let manager = CMMotionActivityManager()
  private let queue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "dev.glandais.autoride.activity"
    queue.maxConcurrentOperationCount = 1
    return queue
  }()
  private var channel: FlutterMethodChannel?
  private var isRunning = false

  // MARK: - Dart-facing API

  /// Starts the updates when the user has authorised them, and answers with
  /// the authorisation either way: `granted` means updates are running,
  /// anything else (`notDetermined`, `denied`, `restricted`, `unavailable`)
  /// means nothing was started and is what the log should say instead.
  private func start() -> String {
    guard CMMotionActivityManager.isActivityAvailable() else { return "unavailable" }
    let status = Self.authorization()
    guard status == "granted" else { return status }
    guard !isRunning else { return status }
    isRunning = true

    manager.startActivityUpdates(to: queue) { [weak self] activity in
      guard let self, let activity else { return }
      let payload = Self.describe(activity)
      DispatchQueue.main.async { self.channel?.invokeMethod("onActivity", arguments: payload) }
    }
    return status
  }

  private func stop() {
    guard isRunning else { return }
    isRunning = false
    manager.stopActivityUpdates()
  }

  private static func authorization() -> String {
    switch CMMotionActivityManager.authorizationStatus() {
    case .authorized: return "granted"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "unknown"
    }
  }

  /// One activity in the vocabulary shared with Android: `k` the primary kind,
  /// `o` the other flags iOS raised at the same time, `cf` the confidence and
  /// `at` the instant iOS says the activity began (ms), which can be well
  /// before the update is delivered.
  ///
  /// iOS raises several flags at once — `automotive` together with
  /// `stationary` at a red light — so the primary is chosen by a fixed
  /// priority, the modes of travel first, and nothing is thrown away: the rest
  /// travel in `o`.
  private static func describe(_ activity: CMMotionActivity) -> [String: Any] {
    var kinds: [String] = []
    if activity.cycling { kinds.append("bike") }
    if activity.automotive { kinds.append("car") }
    if activity.running { kinds.append("run") }
    if activity.walking { kinds.append("walk") }
    if activity.stationary { kinds.append("still") }
    if activity.unknown || kinds.isEmpty { kinds.append("unknown") }

    let confidence: String
    switch activity.confidence {
    case .low: confidence = "low"
    case .medium: confidence = "medium"
    case .high: confidence = "high"
    @unknown default: confidence = "unknown"
    }

    var payload: [String: Any] = [
      "k": kinds[0],
      "cf": confidence,
      "at": Int(activity.startDate.timeIntervalSince1970 * 1000),
    ]
    if kinds.count > 1 { payload["o"] = Array(kinds.dropFirst()) }
    return payload
  }

  // MARK: - Channel

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(FlutterMethodNotImplemented) }
      switch call.method {
      case "start":
        result(self.start())
      case "stop":
        self.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
