# T013: Automatic Trip Start Detection

**Status**: ⏳ In Progress — detector logic shipped, device validation still outstanding.

**Status (2026-09-13)**: The core detection pipeline described below shipped in T041 part 3
(`da3ad62`) — `AutoDetectionController` starts `TripDetectionCoordinator` from the
`automaticDetectionEnabled` setting plus permissions, a manual start button exists, and
auto-pause/stop are reachable during a trip. What remains before T013 can close to ✅ is the
physical-device validation checklist in `tasks/T041-device-validation.md`, per `tasks/TASKS.md`.
Note that the detection *algorithm* itself has continued to evolve past what this file
originally specified — see the windowed motion fit (T050), the vehicle veto (T051), and the
phantom-trip/corroboration fix (T054) in `tasks/CLAUDE.md` and `tasks/LEDGER.md` — so the
threshold values and code sketches below are historical design intent, not the current
implementation.

---

## Summary of what shipped

**Why:** The app needs to start recording a trip automatically when the user begins cycling,
without requiring a manual tap, while rejecting walking/driving and brief false movements.

**Durable decisions:**
- Motion + GPS combined into a confidence score, with motion weighted more heavily when GPS is
  unavailable (grace period before GPS is required).
- Consecutive-detection requirement (not a single spike) gates the state transition, evaluated
  per `AppConstants.detectionEvaluationInterval` rather than every raw sensor sample.
- Cooldown period after a stop prevents rapid start/stop cycling.
- All thresholds live in `AppConstants` (`TripStartDetection` / `tripStart*` constants), not
  hard-coded in the detector.
- `TripStartDetector` and `TripDetectionCoordinator` are Riverpod providers wired into the
  Idle → Detecting → Active trip state machine (T012).

**Delivered:**
`lib/features/trip_detection/domain/models/trip_start_state.dart`,
`lib/features/trip_detection/data/services/trip_start_detector.dart`,
`lib/features/trip_detection/data/services/trip_detection_coordinator.dart`,
`lib/features/trip_detection/presentation/providers/auto_detection_controller.dart`,
`lib/core/constants/app_constants.dart` (detection thresholds),
`test/features/trip_detection/data/services/trip_start_detector_test.dart`.

**Pitfalls:**
- The original single-sample motion fit (this file's Stage 1/Stage 3 sketch) was replaced by a
  windowed accel/gyro fit (T050) after it proved to be a coin toss on real rides — do not treat
  the confidence formula shown further down as current.
- GPS speed voting was found to never actually fire in production (the GPS gate is closed at the
  instant of the start decision) — see L-113/T054 in `tasks/LEDGER.md` before trusting the
  Stage 2 GPS-validation description below as a description of shipped behavior.
- A car is not rejected by the start detector at all; that is `VehicleSpeedWatch`'s job, added
  later (T051).

---

## Remaining work

Physical-device validation of the shipped auto-detection pipeline is still open. It is tracked
as its own checklist, not duplicated here — see `tasks/T041-device-validation.md` (appendix) and
`tasks/LEDGER.md` L-011 for the full specification and wiring plan, and the per-item verdict
procedure in the `autoride-audit-log` skill for how to close a checklist item from a recorded
audit log.

Per `tasks/TASKS.md`, T013 cannot move ⏳ → ✅ until that device-validation checklist is closed.

### Physical Device Tests (from the original T013 checklist, still unverified against current code)
- [ ] Actual cycling triggers automatic start (within 5-10 seconds)
- [ ] Walking does NOT trigger trip start
- [ ] Brief bike movement does NOT trigger (push bike, adjust position)
- [ ] Driving does NOT trigger trip start
- [ ] Indoor cycling (no GPS) triggers after grace period
- [ ] Cooldown prevents immediate restart after false positive

**Note**: given L-079/L-093 (windowed fit) and T054 (phantom trips on a stationary phone —
22 of 26 recorded starts over 26h were phantom), these checks should be re-run and re-verified
against the *current* algorithm rather than assumed to still hold from an earlier build. Treat
this list as the minimum acceptance bar, not as already-passing.

### Integration Testing steps (original Step 6, not yet re-confirmed complete)
```bash
# Physical device required!
```

1. Test on physical device (sensors required)
2. Start cycling and verify automatic trip start
3. Test edge cases:
   - Walking (should NOT trigger)
   - Brief movement (should NOT trigger)
   - Driving (should NOT trigger)
   - Indoor cycling (GPS unavailable)
4. Verify cooldown prevents rapid start/stop
