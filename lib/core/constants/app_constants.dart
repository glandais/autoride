/// App-wide constants for AutoRide
class AppConstants {
  // Prevent instantiation
  AppConstants._();

  // Detection thresholds
  static const double cyclingSpeedMin = 8.0; // km/h
  static const double cyclingSpeedMax = 40.0; // km/h
  // TODO(T041): no consumer — the live detectors use `stationaryAccelerationMax`
  // as the gravity-relative movement threshold.
  static const double movementThreshold = 1.5; // m/s² acceleration

  // Acceleration convention
  // Accelerometer data from sensors_plus includes gravity, so a stationary
  // device reads a magnitude of ~`standardGravity`. All raw-magnitude
  // thresholds in this file assume gravity is INCLUDED.
  static const double standardGravity = 9.8; // m/s²

  // Location settings
  // The live position stream is configured per power mode; see
  // `locationSettingsForPowerMode` and the distance filters below.

  // Timeout for a SINGLE position fix (Geolocator.getCurrentPosition).
  // Deliberately NOT applied to the continuous position stream: a timeLimit
  // there terminates the stream in a tunnel or at a long red light.
  static const int locationTimeLimit = 30; // seconds

  // Continuous location stream resubscription (see `locationStream`).
  // The position stream can end or error (GPS loss, plugin error). Recording
  // must survive that, so the stream provider resubscribes with a capped
  // backoff instead of going permanently silent.
  static const Duration locationStreamRetryDelay = Duration(seconds: 2);
  static const Duration locationStreamMaxRetryDelay = Duration(seconds: 30);

  // ML settings
  // Nominal sampling rate the buffer sizes below are expressed in. The LIVE
  // rate is per power mode (`sensorSamplingRateNormal`…`Critical`), applied by
  // the sensor stream providers.
  static const int sensorSamplingRate = 50; // Hz
  // TODO(T016-T019): unused until the TensorFlow Lite activity classifier lands.
  static const int mlInferenceInterval = 10; // seconds
  static const double confidenceThreshold = 0.85;

  // Battery optimization
  static const int batteryCheckIntervalMinutes = 5;
  static const int criticalBatteryThreshold = 10; // %
  static const int lowBatteryThreshold = 20; // %
  static const int mediumBatteryThreshold = 50; // %
  static const int sensorBufferSize = 3000; // samples (60s at 50Hz)

  // GPS Inactivity Timeout
  // How long the rider must stay stationary (outside a trip) before the
  // coordinator cancels its GPS subscription. See TripDetectionCoordinator.
  static const Duration gpsInactivityTimeout = Duration(seconds: 30);

  // Distance Filters by State
  static const int distanceFilterStationary = 100; // meters
  static const int distanceFilterMoving = 20; // meters
  static const int distanceFilterCycling = 15; // meters (optimal for cycling)

  // Distance Filters by Power Mode (derived from the values above; named so the
  // documented per-mode table is checkable against a constant).
  static const int distanceFilterLowPower = distanceFilterMoving + 10; // 30 m
  static const int distanceFilterCriticalPower =
      distanceFilterStationary ~/ 2; // 50 m

  // Location Update Intervals by Power Mode
  static const Duration locationUpdateNormal = Duration(seconds: 30);
  static const Duration locationUpdateMedium = Duration(seconds: 40);
  static const Duration locationUpdateLow = Duration(seconds: 60);
  static const Duration locationUpdateCritical = Duration(seconds: 90);

  // Sensor Sampling Rates by Power Mode (Hz)
  static const int sensorSamplingRateNormal = 50;
  static const int sensorSamplingRateMedium = 40;
  static const int sensorSamplingRateLow = 25;
  static const int sensorSamplingRateCritical = 20;

  // Cycling Detection Thresholds (T008)

  // Acceleration thresholds (m/s²)
  static const double cyclingAccelerationMin = 10.0; // Minimum for cycling
  static const double cyclingAccelerationMax = 20.0; // Maximum typical cycling
  // TODO(T041): no consumer — walking is currently rejected implicitly by the
  // cycling acceleration band rather than by an explicit walking ceiling.
  static const double walkingAccelerationMax = 12.0; // Walking typically <12

  // Rotation thresholds (rad/s)
  static const double cyclingRotationMin = 0.5; // Minimum rotation for cycling
  static const double cyclingRotationMax = 3.0; // Maximum typical rotation

  // Stationary thresholds (T007)
  //
  // INSTANTANEOUS, single-sample thresholds. Their only consumer is
  // `MotionWindow.state`, which classifies a window for the coordinator's GPS
  // gate (stationary => schedule the GPS subscription to close). They are NOT
  // used by trip stop detection any more — see the windowed thresholds below.
  //
  // Max deviation of raw accelerometer magnitude from gravity while stationary.
  // A resting device reads ~`standardGravity`; |magnitude - gravity| must stay
  // within this tolerance to be considered stationary.
  static const double stationaryAccelerationMax =
      1.0; // m/s² - max deviation from gravity
  static const double stationaryRotationMax = 0.2; // rad/s - max for stationary

  // Windowed stationary thresholds (T041 — trip stop detection)
  //
  // The stop detector evaluates "standing still" over a sliding time window
  // instead of one 50 Hz sample. The instantaneous test above is unusable for
  // a *carried* phone: at a red light with the phone in a pocket the gyroscope
  // reads 0.1-0.5 rad/s on individual samples, so `stationaryRotationMax` (0.2)
  // fails constantly, auto-pause almost never fires and the 5-minute auto-stop
  // is unreachable. Averaged over ~1.5 s the picture is unambiguous.
  //
  // Orders of magnitude these values are chosen against:
  //   at a standstill, phone carried : accel std-dev < 0.5 m/s², gyro mean 0.1-0.5 rad/s
  //   rolling                        : accel std-dev > 1 m/s² (road vibration),
  //                                    gyro mean > 0.5 rad/s
  // The thresholds sit above the standstill band and below the rolling band.

  /// Length of the sliding window the stationary verdict is computed over.
  /// Long enough to average out a single sway or bump (75 samples at 50 Hz),
  /// short enough that a rider pulling away is detected within one evaluation
  /// interval.
  static const Duration stationaryWindowDuration = Duration(milliseconds: 1500);

  /// Hard cap on retained samples, so an unexpectedly high sensor rate cannot
  /// grow the window without bound (1.5 s at 50 Hz is ~75).
  static const int stationaryWindowMaxSamples = 128;

  /// Max standard deviation of the accelerometer magnitude over the window.
  /// Above this the phone is being shaken by road vibration, i.e. rolling.
  static const double stationaryAccelerationStdDevMax = 0.8; // m/s²

  /// Max mean gyroscope magnitude over the window. A pocketed phone at a
  /// standstill averages 0.1-0.5 rad/s; pedalling averages well above 0.5.
  static const double stationaryRotationAverageMax = 0.6; // rad/s

  /// GPS speed below which a fresh fix is treated as "not travelling".
  /// 3 km/h rather than 0 because a stationary GPS commonly reports 1-3 km/h of
  /// noise; well below `cyclingSpeedMin` (8 km/h).
  static const double stationarySpeedMaxKmh = 3.0;

  /// GPS speed above which a fresh fix means "moving", whatever the sensors
  /// say. Covers the phone lying still in a pannier or basket, where the
  /// accelerometer and gyroscope can both look calm while the bike rolls.
  static const double movingSpeedMinKmh = 6.0;

  /// How old a fix may be before its speed is ignored by stop detection.
  /// Beyond this the position stream has likely stalled (tunnel, gate closed),
  /// and a stale "0 km/h" must not be read as a standstill.
  static const Duration stationaryGpsMaxAge = Duration(seconds: 10);

  // Pedaling frequency (Hz)
  static const double pedalingFrequencyMin = 0.5; // 30 RPM minimum
  static const double pedalingFrequencyMax = 2.0; // 120 RPM maximum
  static const double pedalingFrequencyTypical = 1.2; // 72 RPM typical

  // Speed validation (km/h) - extending existing
  static const double cyclingSpeedTypical = 18.0; // Typical commuting speed

  // Pattern analysis
  static const int minSamplesForPattern = 100; // ~2 seconds at 50Hz
  static const int pedalingCycleSamples = 50; // ~1 second for one pedal cycle

  // Confidence thresholds
  // TODO(T041): consumed only by CyclingPatternDetector, which has no live
  // entry point yet; the running trip-start path uses
  // `tripStartConfidenceThreshold` instead.
  static const double minConfidenceForDetection = 0.6; // Minimum to trigger
  static const double highConfidenceThreshold = 0.8; // High confidence

  // Activity classification weights
  static const double motionScoreWeight = 0.4; // 40% weight
  static const double speedScoreWeight = 0.35; // 35% weight
  static const double frequencyScoreWeight = 0.25; // 25% weight

  // Trip State Machine Configuration (T012)
  static const int detectionTimeoutSeconds =
      30; // Max time in Detecting before timeout
  // (`stationaryThresholdSeconds` used to sit here with a TODO and no consumer;
  // removed in T041 — the stop detector gates the pause on
  // `minPauseDurationSeconds` + consecutive stationary detections.)
  static const int maxPauseDurationSeconds =
      300; // 5 min - max pause before auto-stop
  static const int resumeMovementThresholdSeconds =
      5; // Movement time before resume

  // Trip Start Detection Configuration (T013)

  // Confidence threshold to trigger trip start (0.0-1.0)
  static const double tripStartConfidenceThreshold = 0.7;

  // Minimum consecutive detections before starting trip.
  // A "detection" is one evaluation slot of `detectionEvaluationInterval`, NOT
  // one 50 Hz sensor sample — otherwise 3 detections would mean ~60 ms and a
  // single bump could start a trip.
  static const int tripStartMinConsecutiveDetections = 3;

  // Time window for consecutive detection counting (seconds).
  // Maximum gap between two counted detections before the streak resets.
  static const int tripStartDetectionWindowSeconds = 5;

  // Detection evaluation cadence (shared by trip start and trip stop).
  //
  // Both detectors are fed every motion sample (50 Hz). Counting one detection
  // per sample makes every "consecutive detections" threshold meaningless, so
  // counters only advance once per interval; samples in between still update
  // confidence and pause timers.
  static const Duration detectionEvaluationInterval = Duration(seconds: 1);

  // Cooldown period after false start (seconds)
  static const int tripStartCooldownPeriodSeconds = 30;

  // GPS speed range for cycling validation (km/h)
  // Note: cyclingSpeedMin and cyclingSpeedMax already defined above

  // Grace period before GPS required (seconds)
  // Allows motion-only detection for first N seconds (e.g., GPS lock delay)
  // TODO(T041): no consumer — the detector already falls back to motion-only
  // whenever `location` is null, without an explicit grace period.
  static const int tripStartGpsGracePeriodSeconds = 10;

  // Weighting for confidence calculation
  static const double tripStartMotionWeight = 0.6; // 60% when GPS available
  static const double tripStartSpeedWeight = 0.4; // 40% when GPS available
  // When GPS unavailable, motion weight = 1.0 (100%)

  // Trip Stop Detection Configuration (T014)

  // Minimum pause duration before considering pause state (seconds)
  // Brief stops (< this value) keep trip active
  static const int minPauseDurationSeconds =
      30; // 30s - traffic lights, intersections

  // Maximum pause duration before auto-stop (seconds)
  // Note: maxPauseDurationSeconds already defined above = 300 (5 min)

  // Minimum consecutive stationary detections before pause
  static const int minConsecutiveStationaryDetections = 3;

  // Movement hysteresis / debouncing for stop detection.
  // GPS speed at a true standstill is noisy (often reads 1-4 km/h), so a single
  // transient non-stationary reading must NOT reset the accumulated pause timer.
  // Require this many consecutive non-stationary readings before treating the
  // rider as moving again and resetting the pause accumulation.
  static const int tripStopMovementHysteresisSamples = 3;

  // Minimum movement duration to resume trip (seconds)
  // Note: resumeMovementThresholdSeconds already defined above = 5

  // Stationary thresholds used by the stop detector are the WINDOWED ones
  // defined above (`stationaryAccelerationStdDevMax`,
  // `stationaryRotationAverageMax`, `stationarySpeedMaxKmh`,
  // `movingSpeedMinKmh`, `stationaryGpsMaxAge`). The instantaneous
  // `stationaryAccelerationMax` / `stationaryRotationMax` pair belongs to
  // `MotionWindow.state` / the GPS gate only.

  // Trip Recording Configuration (T015)

  // Route point distance filtering (meters)
  // Reuses cycling distance filter value for consistency
  static const double minRoutePointDistanceMeters = 15.0;

  // Route point buffer size before batch database save
  // 100 points ≈ 2KB memory, saves every ~1.5km at 15m intervals
  static const int routePointBufferSize = 100;

  // Retry policy for persisting the route-point buffer.
  // The final flush at trip stop is the last chance to persist the tail of a
  // ride, so it is retried; if it still fails the points stay buffered (they
  // carry their own trip id) rather than being dropped.
  static const int routePointFlushMaxAttempts = 3;
  static const Duration routePointFlushRetryDelay = Duration(milliseconds: 250);

  // Maximum interval between buffer flushes (seconds)
  // Fallback if distance filter not triggered (ensures data persistence)
  static const int maxRecordingIntervalSeconds = 30;

  // Maximum GPS accuracy threshold (meters)
  // Route points with accuracy > this value are rejected (poor GPS fix)
  static const double maxLocationAccuracyMeters = 50.0;

  // Maximum cycling speed for outlier rejection (km/h)
  // Route points with speed > this value are rejected (likely GPS error)
  // Higher than cyclingSpeedMax to allow safety margin
  static const double maxCyclingSpeedKmh = 60.0;

  // Minimum duration for a recording to be kept as a real trip (seconds).
  // Anything shorter is a false start (a bump, a mis-tap on the manual start
  // button) and is discarded instead of becoming a permanent history entry.
  // Consumed by `Trip.isValidTrip`, the recorder's stop path and the startup
  // recovery of interrupted trips.
  static const int minTripDurationSeconds = 60;

  // Database
  static const String databaseName = 'autoride.db';
  // v2 (L-068): `trips.status` (active/completed/discarded) for trip lifecycle
  // tracking and recovery of recordings interrupted by an app kill.
  // v3 (L-073): `trips.pause_duration` (seconds spent stopped), so `duration`
  // can stay the moving time and the stopped time is still reconstructible
  // after the fact — for history display and for the startup recovery.
  static const int databaseVersion = 3;

  // Onboarding Configuration (T021)
  static const String onboardingCompleteKey = 'onboarding_complete';
  // TODO(T041): unused — the onboarding widgets and provider still hardcode the
  // page count (5) and the 300 ms page transition.
  static const int onboardingPageCount = 5;
  static const Duration onboardingAnimationDuration = Duration(
    milliseconds: 300,
  );
  static const Duration onboardingPageTransitionDuration = Duration(
    milliseconds: 250,
  );

  // Notification Configuration (T025)

  // Notification IDs
  static const int foregroundNotificationId = 888;
  static const int tripStartNotificationId = 100;
  static const int tripStopNotificationId = 101;

  // Notification Channels (Android)
  static const String tripTrackingChannelId = 'autoride_tracking';
  static const String tripTrackingChannelName = 'Trip Tracking';
  static const String tripEventsChannelId = 'autoride_trip_events';
  static const String tripEventsChannelName = 'Trip Events';

  // Notification Texts
  //
  // The foreground service runs for the whole time automatic detection is
  // listening (not just while recording), so its notification has two phases.
  // Kept here rather than inline so both the isolate's initial notification and
  // the live updates pushed by `AutoDetectionController` say the same thing.
  static const String notificationTitleDetecting = 'AutoRide - Auto detection';
  static const String notificationContentDetecting = 'Waiting for a bike trip';
  static const String notificationTitleTrip = 'AutoRide - Trip in progress';

  // Notification Update Intervals
  //
  // Throttles the trip status pushed into the foreground-service notification
  // by `AutoDetectionController`: the recorder's metrics tick once a second,
  // which is far more often than the notification needs to change.
  static const Duration notificationUpdateInterval = Duration(seconds: 5);

  // Legal Documents (T037)
  //
  // Served by GitHub Pages from docs/ on branch develop. privacyPolicyUrl is filed with Google
  // Play (store listing, Data safety form, background-location declaration) and App Store
  // Connect (App Privacy), so changing it means updating those consoles too — see
  // store-metadata/data-safety.md §9 for the full list of places it appears.
  static const String privacyPolicyUrl =
      'https://glandais.github.io/autoride/legal/privacy-policy.html';
  static const String termsOfUseUrl =
      'https://glandais.github.io/autoride/legal/terms-of-service.html';
}
