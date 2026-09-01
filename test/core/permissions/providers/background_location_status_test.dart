import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart'
    hide
        PermissionDeniedException,
        PermissionRequestInProgressException,
        LocationServiceDisabledException,
        ServiceStatus;
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';

import 'package:autoride/core/permissions/exceptions/permission_exceptions.dart';
import 'package:autoride/core/permissions/models/background_location_state.dart';
import 'package:autoride/core/permissions/models/permission_status.dart';
import 'package:autoride/core/permissions/providers/background_location_status.dart';

/// The seams are the plugins' own platform interfaces, as in
/// `permission_handler_service_test.dart`: the provider must ask the OS for
/// `locationAlways` specifically, must ask geolocator for the accuracy on top
/// of it, and must re-ask both on [BackgroundLocationStatus.refresh].
void main() {
  late PermissionHandlerPlatform originalHandler;
  late GeolocatorPlatform originalGeolocator;
  late _FakePermissionHandler handler;
  late _FakeGeolocator geolocator;

  setUp(() {
    originalHandler = PermissionHandlerPlatform.instance;
    originalGeolocator = GeolocatorPlatform.instance;
    handler = _FakePermissionHandler();
    geolocator = _FakeGeolocator();
    PermissionHandlerPlatform.instance = handler;
    GeolocatorPlatform.instance = geolocator;
  });

  tearDown(() {
    PermissionHandlerPlatform.instance = originalHandler;
    GeolocatorPlatform.instance = originalGeolocator;
  });

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  group('backgroundLocationStatusProvider', () {
    test('reads locationAlways, not the foreground permission', () async {
      handler.statuses[Permission.locationWhenInUse] = PermissionStatus.granted;
      handler.statuses[Permission.locationAlways] =
          PermissionStatus.permanentlyDenied;

      final state = await container().read(
        backgroundLocationStatusProvider.future,
      );

      expect(handler.checked, equals([Permission.locationAlways]));
      expect(state.permission.permission, equals(AppPermission.locationAlways));
      expect(state.permission.isGranted, isFalse);
      expect(state.permission.needsSettings, isTrue);
    });

    test('reports alwaysMissing when the permission is not granted', () async {
      handler.statuses[Permission.locationAlways] =
          PermissionStatus.permanentlyDenied;

      final state = await container().read(
        backgroundLocationStatusProvider.future,
      );

      expect(state.issue, equals(BackgroundLocationIssue.alwaysMissing));
      expect(state.isReady, isFalse);
    });

    test('does not ask for the accuracy when the permission is missing', () async {
      handler.statuses[Permission.locationAlways] = PermissionStatus.denied;
      geolocator.accuracy = LocationAccuracyStatus.reduced;

      final state = await container().read(
        backgroundLocationStatusProvider.future,
      );

      expect(geolocator.accuracyCalls, equals(0));
      // The permission is the issue to report, so the unread accuracy must not
      // masquerade as a second problem.
      expect(state.accuracy, equals(LocationAccuracyStatus.precise));
      expect(state.issue, equals(BackgroundLocationIssue.alwaysMissing));
    });

    test(
      'reports preciseMissing for "Always" with approximate location',
      () async {
        handler.statuses[Permission.locationAlways] = PermissionStatus.granted;
        geolocator.accuracy = LocationAccuracyStatus.reduced;

        final state = await container().read(
          backgroundLocationStatusProvider.future,
        );

        expect(geolocator.accuracyCalls, equals(1));
        expect(state.permission.isGranted, isTrue);
        expect(state.issue, equals(BackgroundLocationIssue.preciseMissing));
        expect(state.isReady, isFalse);
      },
    );

    test('is ready only for a real "Always" with precise location', () async {
      handler.statuses[Permission.locationAlways] = PermissionStatus.granted;
      geolocator.accuracy = LocationAccuracyStatus.precise;

      final state = await container().read(
        backgroundLocationStatusProvider.future,
      );

      expect(state.isReady, isTrue);
      expect(state.issue, isNull);
    });

    test('refresh re-reads the OS and exposes the new value', () async {
      handler.statuses[Permission.locationAlways] =
          PermissionStatus.permanentlyDenied;
      final c = container();
      // Kept alive: a keepAlive provider with no listener would not rebuild.
      final sub = c.listen(backgroundLocationStatusProvider, (_, _) {});
      addTearDown(sub.close);

      expect(
        (await c.read(backgroundLocationStatusProvider.future)).isReady,
        isFalse,
      );

      // The user picked "Always" in system settings while the app was away.
      handler.statuses[Permission.locationAlways] = PermissionStatus.granted;
      c.read(backgroundLocationStatusProvider.notifier).refresh();

      expect(
        (await c.read(backgroundLocationStatusProvider.future)).isReady,
        isTrue,
      );
      expect(handler.checked.length, equals(2));
    });
  });
}

class _FakePermissionHandler extends PermissionHandlerPlatform {
  final statuses = <Permission, PermissionStatus>{};
  final checked = <Permission>[];

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    checked.add(permission);
    return statuses[permission] ?? PermissionStatus.denied;
  }
}

class _FakeGeolocator extends GeolocatorPlatform {
  LocationAccuracyStatus accuracy = LocationAccuracyStatus.precise;
  int accuracyCalls = 0;

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async {
    accuracyCalls++;
    return accuracy;
  }
}
