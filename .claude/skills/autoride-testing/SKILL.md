---
name: autoride-testing
description: How to write and run tests for AutoRide, including mocking Riverpod providers with ProviderContainer overrides, unit vs widget test layout, and the physical-device test scenario checklist for sensor and GPS features. Use when writing tests, mocking providers, or planning device testing.
---

# Testing (AutoRide)

Run `flutter analyze` before `flutter test` — analysis must pass first.

## Test Types

**Unit Tests** (business logic):
```bash
flutter test test/features/trip_detection/data/services/
```

**Widget Tests** (UI with mocked providers):
```bash
flutter test test/features/trip_detection/presentation/
```

**Integration Tests** (not yet implemented)

## Physical Device Testing

Sensor and location features **MUST** be tested on physical devices — emulators do not
produce usable sensor data.

**Test Scenarios**:
- [ ] Cycling trip (10+ minutes)
- [ ] Walking trip (false positive check)
- [ ] Driving trip (false positive check)
- [ ] Stationary (no false detection)
- [ ] App backgrounded during trip
- [ ] Low battery scenario (<20%)

### Mocking Providers in Tests

```dart
testWidgets('test description', (tester) async {
  final container = ProviderContainer(
    overrides: [
      myServiceProvider.overrideWith((ref) => MockMyService()),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MyApp(),
    ),
  );

  // Test implementation
});
```

## Test Data Must Meet Thresholds

Verify test data mathematically against `AppConstants` before asserting on detection
state. See the `freezed-riverpod-patterns` skill (Mistake #4) for a worked example.
