/// App-wide constants for AutoRide
class AppConstants {
  // Prevent instantiation
  AppConstants._();

  // Detection thresholds
  static const double cyclingSpeedMin = 8.0; // km/h
  static const double cyclingSpeedMax = 40.0; // km/h

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

  // Pre-trip location buffer (L-076)
  //
  // While the GPS gate is open but no trip is recording, the coordinator keeps
  // the fixes it receives so the ride that is confirmed a few seconds later can
  // be back-filled with the metres already covered. Two independent bounds, so
  // neither a stalled clock nor an unexpectedly chatty location plugin can grow
  // it without limit:
  //
  // - 10 minutes of history. It was 90 s until T050, sized on the detection
  //   phase alone — `detectionTimeoutSeconds` (30 s) plus the seconds the
  //   consecutive-detection rule needs plus the recorder's first fix. That is
  //   the *nominal* delay, and the 2026-09-06 ride is what happens when the
  //   detector is late instead: departure at 23:20:50, confirmation at 23:30:38,
  //   and a back-date that could only reach back 86 s and 595 m of the 2.9 km
  //   already ridden, because the rest had aged out of this buffer. The window
  //   has to cover the *worst* confirmation delay, not the intended one.
  //
  //   Nothing older can be prefixed by accident: the buffer is cleared whenever
  //   the GPS gate closes (`gpsInactivityTimeout`, 30 s stationary), so its span
  //   is always one continuous stretch of movement, and `ridingTailOf` then cuts
  //   it back to the first fix at cycling speed.
  // - 256 points. At `minRoutePointDistanceMeters` (15 m) and ~20 km/h a fix
  //   arrives roughly every 3 s, so 10 minutes is about 200; 256 is a guard
  //   against a faster rider or a denser stream, not the operative limit. ~40 kB
  //   of `LocationData` at the bound.
  static const Duration preTripLocationBufferDuration = Duration(minutes: 10);
  static const int preTripLocationBufferMaxPoints = 256;

  /// How long a recording trip may go without a single GPS fix before the
  /// coordinator stops it (L-074). Counted from the last fix, or from the start
  /// of the trip while no fix has arrived yet.
  ///
  /// 10 minutes is chosen against the two failure modes it has to separate:
  /// - a *recoverable* outage — a tunnel, an underground car park, a dense
  ///   urban canyon, a cold restart of the location stream — where fixes come
  ///   back within a couple of minutes and the ride must survive intact. The
  ///   longest realistic road tunnel a cyclist rides through is well under
  ///   5 minutes, so a threshold at 10 minutes leaves a 2x margin;
  /// - a *terminal* one — the phone left in a building, location services
  ///   switched off mid-ride, the GPS chip wedged — where the trip would
  ///   otherwise stay "active" for hours on stray gyroscope noise.
  ///
  /// The cost of the false negative (waiting 10 min) is bounded and cheap: the
  /// tail of the trip carries no route points anyway, and the moving time is
  /// only over-counted by the outage. The cost of stopping too early is losing
  /// the second half of a real ride, so the threshold is deliberately generous.
  /// Note that `maxPauseDurationSeconds` (5 min) already auto-stops any trip
  /// whose *sensors* also go quiet; this timeout only catches the case where
  /// motion continues but positions do not.
  static const Duration gpsLossStopTimeout = Duration(minutes: 10);

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

  // Windowed cycling fit for trip start (T050, L-079)
  //
  // The four bands above are INSTANTANEOUS: they score one 20 ms sample of raw
  // magnitude. `TripStartDetector` used them that way until T050, and on a bike
  // |a| swings between 4 and 24 m/s² from one sample to the next, so the score
  // was a coin toss on whichever sample happened to land on the evaluation
  // boundary. The 2026-09-06 ride measures it: 6.5 % of the sampled instants of
  // a confirmed ride cleared the 0.7 threshold, the streak reached 3 once in
  // 590 s, and the trip started 9 min 50 s and 2.9 km after the real departure.
  //
  // What separates a bike from everything else is not the level of |a| — a
  // still phone reads 9.81 and a pedalling one 10.2 — but its **variability**,
  // and a sustained rotation rate. Both are properties of a *window*, so the
  // start path now scores the last `detectionEvaluationInterval` of samples.
  //
  // The numbers are read off the 1 Hz `sens` series of that log, per phase:
  //
  // | phase                      | std(|a|) | mean |g| |
  // |----------------------------|----------|----------|
  // | phone still on a table     |   0.56   |   0.16   |
  // | carried, walking about     |   1.86   |   0.65   |
  // | the ride that was missed   |   3.90   |   1.32   |
  // | the ride once it started   |   3.39   |   1.08   |
  //
  // Hence a ramp that is 0 at the walking end, saturated at the cycling end,
  // and back to 0 above anything a bicycle produces. Riding scores 1.0 on both
  // arms, walking ~0.57 combined — under the 0.7 threshold, which is what keeps
  // L-093's answer to the kitchen intact.
  //
  // Provisional until a device run: they come from 1 Hz samples, and the real
  // fit runs on the 20–50 Hz stream where the within-second spread is at least
  // as large.
  //
  // The acceleration minimum is the arm that has to clear the walking figure,
  // and it does (2.0 against 1.86) — erring low there is what would start a
  // ride on a walk. The gyroscope minimum deliberately sits *below* it: a
  // pocket swings, so a walk scores about half that arm and nothing at all on
  // the other, and half of half a score cannot reach 0.7.

  /// Standard deviation of accelerometer magnitude (m/s²) below which a window
  /// is not cycling at all.
  static const double cyclingAccelStdMin = 2.0;

  /// …and at which it scores full marks. Between the two the score ramps.
  static const double cyclingAccelStdIdeal = 3.0;

  /// Above this the shaking is not a bicycle (a dropped phone, a washing
  /// machine, a train coupling) and the arm scores 0.
  static const double cyclingAccelStdMax = 12.0;

  /// Mean gyroscope magnitude (rad/s) below which a window is not cycling.
  static const double cyclingGyroMeanMin = 0.4;

  /// …and at which it scores full marks.
  static const double cyclingGyroMeanIdeal = 0.9;

  /// Above this the rotation is not a bicycle carrying a phone.
  static const double cyclingGyroMeanMax = 3.0;

  /// Samples a window must hold before it is allowed to score above zero.
  ///
  /// A standard deviation over two samples is noise. Five is half a second at
  /// the critical power mode's 20 Hz — the slowest stream the app configures —
  /// so the requirement never costs more than the first evaluation interval.
  static const int tripStartMotionWindowMinSamples = 5;

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

  // Speed trust (T048 — L-087, L-088, L-089)
  //
  // The problem these three answer: a fix that is *present* and reports a bogus
  // 0 km/h scores `speedScore` 0 and caps the start confidence at
  // `tripStartMotionWeight` (0.60), below the 0.7 threshold — so **no fix at
  // all scores higher than a bad fix**, and a genuine 19 km/h ride cannot be
  // detected while its phone reports zeroes (2026-09-03, both devices).

  /// Accuracy beyond which a fix's *speed* carries no information worth voting
  /// on, so the start path treats it as no fix rather than as zero speed.
  ///
  /// Deliberately its own constant and not `maxLocationAccuracyMeters`, which
  /// answers a different question ("is this point fit to be drawn on a route?").
  /// They happen to share a value today; the reasons to move them are not the
  /// same, so they move separately. On the 2026-09-03 Pixel run 30 of the 40
  /// fixes of the ride sat above this, 29 of them on the round
  /// 100/200/300/500/600/700/800 m of the fused provider's cell/wifi ladder.
  static const double speedTrustMaxAccuracyMeters = 50.0;

  /// How old a fix may be before its speed is ignored by *start* detection.
  ///
  /// The same bound the stop detector has always applied
  /// ([stationaryGpsMaxAge]); the start path simply never applied it, and with
  /// fixes 30.7 s apart the Pixel scored 80 % of its evaluations against a fix
  /// older than this, mean age 33.6 s.
  static const Duration speedTrustMaxAge = stationaryGpsMaxAge;

  // Derived speed (T048 — L-087)
  //
  // When the provider reports no speed at all, it is computed from the
  // displacement since the previous fix. iOS delivered `sp` 0 on 88 % of the
  // fixes of a 19 km/h ride, and the pre-trip buffer's riding-tail cut — which
  // looks for the first fix at `cyclingSpeedMin` — read all 14 of its fixes as
  // stationary, which is why that ride's back-date recovered 3 s instead of the
  // 1.3 km it had already covered.

  /// Shortest gap between two fixes worth deriving a speed from. Below this the
  /// position noise dominates the displacement and the quotient explodes.
  static const Duration derivedSpeedMinGap = Duration(seconds: 1);

  /// Longest gap worth deriving a speed from, as a multiple of the interval the
  /// current power mode actually asks for
  /// (`PowerModeConfig.derivedSpeedMaxGap`). Beyond it the average says little
  /// about the instant being scored, and a gap that long usually means the
  /// stream stalled rather than that the rider crossed the distance smoothly.
  ///
  /// **A fixed bound cannot work here, and the first version of T048 shipped
  /// one.** It was 30 s, against a [locationUpdateNormal] of exactly 30 s — and
  /// since `intervalDuration` is a request the OS serves with jitter, every
  /// Android gap lands just above it. Replaying the estimator over the
  /// 2026-09-03 Pixel logs derives a speed **0 times on both rides**: 14 pairs
  /// of the morning ride, accurate to 14–43 m and sitting a median 11 m from
  /// the Strava track, were refused for 30.7 s against a 30 s bound. The other
  /// modes are worse — 40, 60 and 90 s are all above it — so §3.1 of the task
  /// was, as shipped, an iOS-only fix by accident: iOS ignores
  /// `intervalDuration` and delivers on the distance filter, 6–15 s apart.
  ///
  /// Tying the bound to the interval is what makes it a bound rather than a
  /// coincidence. The guards that do the real filtering are unchanged: both
  /// fixes accurate, displacement above the noise it is measured through, and
  /// the quotient below [maxCyclingSpeedKmh].
  static const double derivedSpeedMaxGapFactor = 1.5;

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
  //
  // How long the machine may sit in `Detecting` without confirming a ride. On
  // expiry it returns to idle and the start detector's streak is dropped —
  // nothing else: no cooldown, no stream teardown (L-075), so a real departure
  // one second later is still caught.
  static const int detectionTimeoutSeconds = 30;
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

  // Staleness bound on the consecutive-detection streak (seconds).
  //
  // NOT a sliding window any more (L-093). The streak is now truly
  // consecutive: it dies on the first evaluation interval that scores below
  // `tripStartConfidenceThreshold`, so a positive detection is required in
  // every second of it. This constant only answers the case where no sample
  // arrives at all — a suspended process, a sensor stream that stalled — where
  // there is no interval to score and an hour-old streak must not be resumed
  // as if it were current.
  //
  // What it used to mean, and why that was the defect: `lastDetectionTime` was
  // refreshed on every positive detection and the comparison truncated to whole
  // seconds, so "3 detections" meant three spikes each within 5.99 s of the
  // previous one — up to 18 s of wall clock with any number of near-zero
  // samples in between. All ten false starts of the 2026-09-03 kitchen run are
  // that signature.
  static const int tripStartDetectionWindowSeconds = 5;

  // Detection evaluation cadence (shared by trip start and trip stop).
  //
  // Both detectors are fed every motion sample (50 Hz). Counting one detection
  // per sample makes every "consecutive detections" threshold meaningless, so
  // counters only advance once per interval; samples in between still update
  // confidence and pause timers.
  static const Duration detectionEvaluationInterval = Duration(seconds: 1);

  // Cooldown period after a false start (seconds).
  //
  // "False start" means a trip that really was started and then discarded for
  // being shorter than `minTripDurationSeconds` — the only case where the
  // detector has demonstrably been fooled and whatever fooled it is probably
  // still happening. A `Detecting` phase that merely times out is NOT a false
  // start and does not arm this (L-075).
  static const int tripStartCooldownPeriodSeconds = 30;

  // GPS speed range for cycling validation (km/h)
  // Note: cyclingSpeedMin and cyclingSpeedMax already defined above

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

  // Minimum ratio between a displacement and the uncertainty of the fix that
  // produced it, for that fix to become a route point (L-094).
  //
  // `minRoutePointDistanceMeters` (15 m) and `maxLocationAccuracyMeters` (50 m)
  // are independent, and one is three times the other in the wrong direction: a
  // fix accurate to +/-30 m clears a 15 m displacement gate on noise alone. The
  // 2026-09-03 kitchen run recorded 183 m from nine points that all sat inside
  // a ~40 m square around the house (`rp keep d=18.2 ac=33.5`). Requiring the
  // displacement to beat the accuracy makes drift stop counting as distance,
  // without moving either bound.
  //
  // 1.0 — the displacement must simply exceed the fix's own error bar. Higher
  // would also reject the slow start of a real ride under a poor sky.
  static const double routePointAccuracyRatio = 1.0;

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
  // Consumed by `Trip.isRideWorthKeeping`, the recorder's stop path and the
  // startup recovery of interrupted trips.
  static const int minTripDurationSeconds = 60;

  // Minimum route points for a recording to be kept as a real trip.
  //
  // Two, because that is the fewest that can describe a movement at all: one
  // point is a position, and `TripRecoveryService.rebuildFromRoutePoints` has
  // always refused to rebuild a ride from fewer. The live stop path had no such
  // rule, which is how the 2026-09-02 control run put two 0 m recordings in
  // History — 627 s on a single rejected fix, and 134 s with no fix at all
  // (L-081). Consumed by `Trip.isRideWorthKeeping`.
  static const int minTripRoutePoints = 2;

  // Minimum net displacement (start to end, in meters) for a recording to be
  // kept as a real trip, when its average speed does not vouch for it (L-095).
  //
  // Twice `maxLocationAccuracyMeters`: a recording whose endpoints are inside
  // the error bar of the fixes that produced them has no evidence of having
  // gone anywhere. The 2026-09-03 kitchen run wrote 183 m over 930 s whose
  // start and end are ~20 m apart.
  //
  // Net displacement and not total distance, because drift accumulates and a
  // loop does not — which is also why this arm is an OR with the speed one
  // below: a ride that comes home is displacement 0 and speed 20 km/h.
  static const double minTripNetDisplacementMeters =
      2 * maxLocationAccuracyMeters;

  // Minimum average speed (km/h) for a recording to be kept as a real trip,
  // when its net displacement does not vouch for it (L-095).
  //
  // Half of `cyclingSpeedMin` (8 km/h), because `avgSpeed` is measured over the
  // MOVING time only and a legitimate ride can still average low — a walk
  // alongside the bike, a climb, a rider who is simply slow. The two false
  // trips of the 2026-09-03 run averaged 2.5 and 1.4 km/h.
  static const double minTripAvgSpeedKmh = cyclingSpeedMin / 2;

  // Database
  static const String databaseName = 'autoride.db';
  // v2 (L-068): `trips.status` (active/completed/discarded) for trip lifecycle
  // tracking and recovery of recordings interrupted by an app kill.
  // v3 (L-073): `trips.pause_duration` (seconds spent stopped), so `duration`
  // can stay the moving time and the stopped time is still reconstructible
  // after the fact — for history display and for the startup recovery.
  static const int databaseVersion = 3;

  // Audit Log (T043) — the opt-in diagnostic journal
  //
  // A separate database from `autoride.db` on purpose. The log is disposable
  // and the trips are not, so clearing it is one `deleteDatabase()` and a
  // corrupt journal can never threaten ride history. It also lets the journal
  // run WAL + `synchronous = NORMAL` without relaxing anything on the trip
  // database — which matters because an fsync charged to the trip database on
  // every audit batch would bias the very battery-drain measurement of
  // `tasks/T041-device-validation.md` item 4. The observer has to stay neutral.
  static const String auditDatabaseName = 'autoride_audit.db';
  static const int auditDatabaseVersion = 2;

  // Retention: whichever bound is reached first. The byte bound is not
  // redundant with the row bound — at ~130 bytes per line, 200 000 rows is
  // ~26 MB, above the 20 MB the log is allowed to occupy.
  static const Duration auditRetention = Duration(days: 7);
  static const int auditMaxEvents = 200000;
  static const int auditMaxBytes = 20 * 1024 * 1024;

  // A batch is ~26 KB, which commits in a few ms under WAL. Ten times smaller
  // would multiply commits for no latency gain; ten times larger would put
  // minutes of events at the mercy of a Doze kill.
  static const int auditFlushBatchSize = 200;
  static const Duration auditFlushInterval = Duration(seconds: 5);

  // Backstop for a stalled or full disk: past this the oldest buffered lines
  // are dropped and the gap is *declared* (an `aud` event) rather than left
  // silent. The log must never take down the app it observes.
  static const int auditMaxBufferedEvents = 5000;

  // Purge is amortised over writes (~one purge every 2 h at normal level)
  // instead of running on a timer that would fire while nothing is happening.
  static const int auditPurgeWriteInterval = 20000;
  static const int auditPurgeChunkSize = 20000;

  // Liveness proof, on the coordinator's existing 1 Hz supervisor. Without it
  // a gap in the timeline cannot distinguish "the OS suspended the process"
  // from "the log lost its buffer", which are opposite verdicts for items 3
  // and 8 of the device checklist.
  static const Duration auditHeartbeatInterval = Duration(seconds: 30);

  // Past this much drift between the wall clock and the monotonic clock, a
  // fresh `clk` event is emitted: an NTP correction mid-session otherwise
  // poisons the median used to align the log against a Strava FIT.
  static const Duration auditClockDriftThreshold = Duration(seconds: 2);

  // Verbose-only sensor aggregates are throttled to this; the raw stream is
  // 50 Hz and is never recorded.
  static const Duration auditSensorSampleInterval = Duration(seconds: 1);

  // Same treatment for the stationary window verdict (`win`), which is also
  // evaluated per motion sample: a change of verdict or of deciding arm is
  // always recorded, and the repeats in between are collapsed to this rate.
  // Unthrottled it was 80 103 lines of one 2026-09-02 log — over half the file
  // — for 26 minutes of recording (L-085).
  static const Duration auditWindowVerdictInterval = Duration(seconds: 1);

  // Rows read per page when exporting. Keyset pagination, never OFFSET.
  static const int auditExportPageSize = 5000;

  // Training capture (T034) — the second axis of the same log
  //
  // Capture rows (`lvl` 2) share the audit database with the journal and are
  // budgeted separately, because their rate is an order of magnitude higher:
  // ~8 MB/h against the journal's ~2 at verbose. One shared bound would mean
  // an hour of capture purging a whole day of journal, or the reverse.
  //
  // 256 MB is ~30 h of labelled sessions at the rate below. It is a projection
  // from `captureBatchDuration` and the line shape, not a device measurement —
  // `tasks/T034-data-collection.md` §8 asks for the measured MB/h.
  static const int captureMaxBytes = 256 * 1024 * 1024;

  // Longer than the journal's 7 days: the journal is a rolling record of what
  // just happened, a corpus is worked on over weeks.
  static const Duration captureRetention = Duration(days: 30);

  // The array window. One row per second holds a second of samples, which is
  // 3 600 rows/h — under 2 % of `auditMaxEvents` — where one row per sample at
  // 50 Hz would be 180 000 and exhaust both journal bounds in about an hour.
  static const Duration captureBatchDuration = Duration(seconds: 1);

  // Backstop on the array length, for an OS that over-delivers against the
  // requested period: a Pixel 6a measured 83 Hz foregrounded for a configured
  // 50 (L-086). Past this the surplus samples of the window are dropped and
  // the line's `n` says how many were kept.
  static const int captureMaxSamplesPerLine = 128;

  // Capture pins the sampling rate rather than following the power mode: a
  // windowed classifier trained on a corpus whose rate silently drops from 50
  // to 20 Hz with the battery learns the battery, not the activity. The cost
  // is that a capture session is a `normal`-mode session, which is why item 4
  // of the T041 checklist must be measured with capture OFF.
  static const int captureSamplingRate = sensorSamplingRateNormal;

  // Onboarding Configuration (T021)
  static const String onboardingCompleteKey = 'onboarding_complete';

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
