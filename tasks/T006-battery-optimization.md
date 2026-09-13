# T006: Battery-Optimized Location Strategy

## Status

⏳ Partially done, as of 2026-09-13. The design from this guide shipped, but not as
originally sketched: `PowerModeConfig`/`BatteryOptimizer` and `AdaptiveLocationSettings` are in
place and unit/integration-tested, but the standalone `GPSController` this guide proposed was
never built that way — motion-gated GPS was instead folded into `TripDetectionCoordinator`
(T041 part 2, `529db42`), and `GPSController` does not exist in the tree. What remains is
entirely device validation: `tasks/T041-device-validation.md` items **1** (GPS stops when
stationary) and **4** (battery drain ≤ ~5 %/hr) are still open, and until they pass this task
does not close (see `tasks/TASKS.md` T006 entry). Both are pure on-device work — nothing here
is blocked on more code.

**Dependencies**: T005 (Background Location Tracking), T007 (Sensor Integration)
**Target**: <5% battery drain per hour of active tracking (unmeasured)

## What shipped

**Why:** the app needs to track all day on a charge, so GPS and sensor sampling must scale
down as the battery drains and shut off entirely while the rider is stationary.

**Durable decisions:**
- Four named power modes (`normal`/`medium`/`low`/`critical`), selected by battery %, each
  fixing sensor Hz, location update interval, distance filter and `LocationAccuracy` — the
  values are named constants in `AppConstants`, not literals in the mode table.
- Motion-gated GPS lives inside `TripDetectionCoordinator`'s gate, not in a separate
  `GPSController` provider as originally planned here — that class was never built; the gate
  design superseded it in T041 part 2 (`529db42`).
- `AdaptiveLocationSettings` is the single place a `PowerModeConfig` becomes real
  `LocationSettings`, built per platform (`AndroidSettings` vs `AppleSettings`) since the
  update-interval concept isn't portable. It deliberately carries **no** `timeLimit`: Geolocator
  throws `TimeoutException` and kills the stream on a gap (tunnel, urban canyon, a long red
  light), which used to freeze a recording trip's distance for the rest of the ride.
- `battery_plus` drives battery-level monitoring (5-minute periodic check + `onBatteryStateChanged`
  listener); every power-mode change and battery reading is written to the audit log
  (`AuditEvent.powerMode`, `bat`), because item 4's %/hour figure is unmeasurable without knowing
  which sampling rate and distance filter were in force at the time.

**Delivered:** `lib/features/trip_detection/data/services/battery_optimizer.dart`,
`lib/features/trip_detection/data/services/adaptive_location_settings.dart`,
`lib/features/trip_detection/data/services/trip_detection_coordinator.dart` (owns the GPS gate),
`lib/core/constants/app_constants.dart` (power-mode constants),
`test/features/trip_detection/data/services/battery_optimizer_test.dart`,
`test/features/trip_detection/data/services/adaptive_location_settings_test.dart`,
`test/features/trip_detection/data/services/trip_detection_coordinator_test.dart`.

**Pitfalls:**
- Don't look for `gps_controller.dart` — it never shipped; the gate is inside the coordinator.
- Don't reintroduce a `timeLimit` on the continuous position stream — it terminates the stream on
  any gap instead of just skipping a fix.

## Remaining work

Everything below is copied unchanged from the original guide — it is the on-device validation
protocol that `tasks/T041-device-validation.md` items 1 and 4 still need, and it has not been run.

### Physical Device Testing

- [ ] **Battery Profiling** (Critical):
  - Android: Use Android Studio Battery Profiler
  - iOS: Use Xcode Energy Log
  - Test scenario: 1-hour continuous cycling simulation
  - Target: <5% battery drain per hour

- [ ] **GPS Accuracy**:
  - Verify route accuracy with motion-gated GPS
  - Compare with always-on GPS baseline
  - Ensure no significant degradation

- [ ] **State Transitions**:
  - Stationary → Moving: GPS activates within 5 seconds
  - Moving → Stationary (30s): GPS deactivates correctly
  - Low battery mode: Reduced sampling rates applied

- [ ] **Battery Level Scenarios**:
  - Normal (>50%): Full performance
  - Medium (20-50%): Reduced but acceptable
  - Low (<20%): Minimal features, still functional
  - Critical (<10%): Essential features only

### Battery Profiling Guide

#### Android Battery Profiling

1. **Enable Profiler in Android Studio**:
   - Run app in debug mode
   - Open Profiler tab (View → Tool Windows → Profiler)
   - Select Energy profiler

2. **Test Scenario**:
   - Start app with full battery (or note starting percentage)
   - Simulate 1-hour cycling trip:
     - Shake device periodically to simulate motion
     - Move outdoors for real GPS tracking
   - Record battery percentage before/after

3. **Analysis**:
   - Check "Energy usage" graph
   - Look for GPS, Sensors, CPU spikes
   - Identify high consumption periods
   - Target: <5% battery drain per hour

#### iOS Battery Profiling

1. **Enable Energy Log in Xcode**:
   - Run app on physical device
   - Open Debug Navigator (⌘+7)
   - Select "Energy Impact"

2. **Test Scenario**:
   - Same as Android (1-hour cycling simulation)
   - Monitor "Energy Impact" graph
   - Note "Overhead" and "Average" values

3. **Analysis**:
   - "Very High" impact is bad
   - "Low" or "Medium" is acceptable
   - Check location, motion, and processing usage

### Performance Targets

#### Battery Consumption
- **Target**: <5% per hour of active tracking
- **Acceptable**: <8% per hour
- **Unacceptable**: >10% per hour

#### GPS Accuracy
- **Target**: 90% of points within 15m of actual route
- **Acceptable**: 80% of points within 20m
- **Unacceptable**: <70% accuracy

#### State Transition Speed
- **Target**: <3 seconds from motion detection to GPS activation
- **Acceptable**: <5 seconds
- **Unacceptable**: >10 seconds

#### Memory Usage
- **Target**: <50 MB additional memory for battery optimization
- **Acceptable**: <75 MB
- **Unacceptable**: >100 MB

### Pitfall: Battery Drain Still High (investigation steps, if item 4 fails)

**Investigation Steps**:
1. Profile with Android Studio Battery Profiler
2. Check if GPS is stopping correctly when stationary
3. Verify sensor sampling rates are being reduced
4. Ensure location updates use distance filtering
5. Check for location listener leaks

**Common Causes**:
- GPS not stopping when stationary
- Sensor sampling rate too high (should be 25-50 Hz, not 100 Hz)
- No distance filtering (causes constant updates)
- Multiple location listeners active

## Next Steps

Once items 1 and 4 pass on-device, close T006 in `tasks/TASKS.md` and update
`tasks/T041-device-validation.md`'s checklist accordingly.
