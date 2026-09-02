import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/features/trip_detection/services/background_location_service.dart';

/// Reproduces the real call shape: an `await` inside `startTracking`, then a
/// write to `state`. That is what `AutoDetectionController` triggers, and what
/// used to throw.
class _AsyncBackgroundLocationService extends BackgroundLocationService {
  bool started = false;

  @override
  Future<bool> build() async => false;

  @override
  Future<void> initialize() async {
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> startTracking() async {
    await Future<void>.delayed(Duration.zero);
    state = const AsyncValue.data(true);
    started = true;
  }
}

void main() {
  group('BackgroundLocationService', () {
    test('should have service class available', () {
      // This test verifies the service class can be instantiated
      // Actual functionality requires platform channel testing
      expect(BackgroundLocationService, isNotNull);
    });

    // Note: Full integration tests for background services require
    // physical devices as they don't work properly in emulators.
    // Platform channel mocking would be needed for more extensive unit tests.

    test('onStart function should be defined', () {
      // Verify the entry point function exists
      expect(onStart, isNotNull);
    });

    test('onIosBackground function should be defined', () {
      // Verify the iOS background handler exists
      expect(onIosBackground, isNotNull);
    });

    // The provider is only ever reached through `ref.read(...notifier)` — no
    // watch, no listen — so an autoDispose element would have no subscriber and
    // be destroyed at the first async gap. `startTracking` writes `state` after
    // an `await`, and the whole foreground service silently stopped starting
    // (2026-09-02 iPhone audit: an `UnmountedRefException` swallowed by the
    // controller's catch). These two tests pin the invariant that fix rests on.
    test('survives an async gap after a bare ref.read', () async {
      final container = ProviderContainer(
        overrides: [
          backgroundLocationServiceProvider.overrideWith(
            _AsyncBackgroundLocationService.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(
        backgroundLocationServiceProvider.notifier,
      ) as _AsyncBackgroundLocationService;

      await service.initialize();
      await service.startTracking();

      expect(service.started, isTrue);
      expect(container.read(backgroundLocationServiceProvider).value, isTrue);
    });

    test('keeps one instance across reads', () async {
      final container = ProviderContainer(
        overrides: [
          backgroundLocationServiceProvider.overrideWith(
            _AsyncBackgroundLocationService.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      final first = container.read(backgroundLocationServiceProvider.notifier);
      await pumpEventQueue();
      final second = container.read(backgroundLocationServiceProvider.notifier);

      // A new instance here means a new `FlutterBackgroundService()` and a new
      // `build()` on every read, on top of the disposal race above.
      expect(identical(first, second), isTrue);
    });
  });
}
