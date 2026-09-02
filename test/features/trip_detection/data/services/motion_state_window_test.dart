import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/trip_detection/data/services/motion_state_window.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';

/// The window that stopped the GPS gate from flapping.
///
/// The defect it fixes is visible in a T043 audit log: 93 `gate sched` lines
/// for a single `gate close` on a phone lying still, because the gate
/// classified one isolated sample per call and sensor noise flipped that
/// verdict several times a second. Each flip cancelled and re-armed the 30 s
/// inactivity timer, so it never elapsed and GPS never stopped.
void main() {
  final start = DateTime(2026, 1, 1, 12);

  /// A resting phone: gravity-only acceleration, no rotation.
  MotionData calm(int index) {
    final timestamp = start.add(Duration(milliseconds: index));
    return MotionData(
      accelerometer: AccelerometerData(
        x: 0.0,
        y: 0.0,
        z: AppConstants.standardGravity,
        timestamp: timestamp,
      ),
      gyroscope: GyroscopeData(x: 0.0, y: 0.0, z: 0.0, timestamp: timestamp),
      timestamp: timestamp,
    );
  }

  /// A sample well outside the stationary thresholds.
  MotionData agitated(int index) {
    final timestamp = start.add(Duration(milliseconds: index));
    return MotionData(
      accelerometer: AccelerometerData(
        x: 3.0,
        y: 3.0,
        z: 10.0,
        timestamp: timestamp,
      ),
      gyroscope: GyroscopeData(x: 1.0, y: 0.5, z: 0.5, timestamp: timestamp),
      timestamp: timestamp,
    );
  }

  test('an empty window knows nothing', () {
    expect(MotionStateWindow().state, MotionState.unknown);
    expect(MotionStateWindow().isEmpty, isTrue);
  });

  test('a single sample is classified on its own, as before', () {
    final window = MotionStateWindow()..add(calm(0), start);

    expect(window.state, MotionState.stationary);
  });

  test('one noisy sample does not unseat a calm window', () {
    final window = MotionStateWindow();
    for (var i = 0; i < 20; i++) {
      window.add(calm(i), start.add(Duration(milliseconds: i * 20)));
    }
    expect(window.state, MotionState.stationary);

    // The flap: a single sample over the thresholds, exactly what used to
    // cancel the gate's inactivity timer.
    window.add(agitated(21), start.add(const Duration(milliseconds: 420)));

    expect(window.state, MotionState.stationary);
  });

  test('sustained movement does move the verdict', () {
    final window = MotionStateWindow();
    for (var i = 0; i < 20; i++) {
      window.add(calm(i), start.add(Duration(milliseconds: i * 20)));
    }

    for (var i = 20; i < 60; i++) {
      window.add(agitated(i), start.add(Duration(milliseconds: i * 20)));
    }

    expect(window.state, isNot(MotionState.stationary));
  });

  test('samples older than the window are dropped', () {
    final window = MotionStateWindow()..add(agitated(0), start);
    expect(window.length, 1);

    window.add(
      calm(1),
      start
          .add(AppConstants.stationaryWindowDuration)
          .add(const Duration(milliseconds: 1)),
    );

    // The agitated sample aged out, so the calm one decides alone.
    expect(window.length, 1);
    expect(window.state, MotionState.stationary);
  });

  test('the buffer is capped even if the clock never advances', () {
    final window = MotionStateWindow();

    for (var i = 0; i < AppConstants.stationaryWindowMaxSamples * 2; i++) {
      window.add(calm(i), start);
    }

    expect(window.length, AppConstants.stationaryWindowMaxSamples);
  });

  test('clear empties it', () {
    final window = MotionStateWindow()..add(calm(0), start);

    window.clear();

    expect(window.isEmpty, isTrue);
    expect(window.state, MotionState.unknown);
  });
}
