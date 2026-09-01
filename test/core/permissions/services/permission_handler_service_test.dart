import 'dart:async';

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
import 'package:autoride/core/permissions/models/permission_status.dart';
import 'package:autoride/core/permissions/services/permission_handler_service.dart';
import 'package:autoride/core/platform/models/platform_info.dart';
import 'package:autoride/core/platform/services/platform_info_service.dart';

/// Tests for the real [PermissionHandlerService].
///
/// The seams are the plugins' own platform interfaces —
/// `PermissionHandlerPlatform.instance` and `GeolocatorPlatform.instance` —
/// plus a Riverpod override of `platformInfoServiceProvider`, so no test-only
/// hook is added to production code.
///
/// The exception-model tests that used to make up this whole file, and never
/// imported the service (L-026), are kept at the bottom.
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

  PermissionHandlerService serviceOn({PlatformInfo platform = _android10}) {
    final container = ProviderContainer(
      overrides: [
        platformInfoServiceProvider.overrideWith(
          () => _FakePlatformInfoService(platform),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container.read(permissionHandlerServiceProvider.notifier);
  }

  // ---------------------------------------------------------------------------
  // checkPermission / permission mapping
  // ---------------------------------------------------------------------------

  group('PermissionHandlerService.checkPermission', () {
    test('maps every AppPermission onto its permission_handler twin', () async {
      final service = serviceOn();

      await service.checkPermission(AppPermission.locationWhenInUse);
      await service.checkPermission(AppPermission.locationAlways);
      await service.checkPermission(AppPermission.notification);
      await service.checkPermission(AppPermission.activityRecognition);

      expect(
        handler.checked,
        equals([
          Permission.locationWhenInUse,
          Permission.locationAlways,
          Permission.notification,
          Permission.activityRecognition,
        ]),
      );
    });

    test('translates a granted platform status', () async {
      handler.statuses[Permission.locationWhenInUse] = PermissionStatus.granted;

      final status = await serviceOn().checkPermission(
        AppPermission.locationWhenInUse,
      );

      expect(status.permission, equals(AppPermission.locationWhenInUse));
      expect(status.isGranted, isTrue);
      expect(status.isDenied, isFalse);
      expect(status.canRequest, isTrue);
    });

    test('translates a permanently denied platform status', () async {
      handler.statuses[Permission.notification] =
          PermissionStatus.permanentlyDenied;

      final status = await serviceOn().checkPermission(
        AppPermission.notification,
      );

      expect(status.isPermanentlyDenied, isTrue);
      expect(status.needsSettings, isTrue);
      expect(status.canRequest, isFalse);
    });
  });

  group('PermissionHandlerService convenience checks', () {
    test('isGranted / hasForegroundLocation / hasBackgroundLocation', () async {
      handler.statuses[Permission.locationWhenInUse] = PermissionStatus.granted;
      handler.statuses[Permission.locationAlways] = PermissionStatus.denied;
      final service = serviceOn();

      expect(await service.isGranted(AppPermission.locationWhenInUse), isTrue);
      expect(await service.hasForegroundLocation(), isTrue);
      expect(await service.hasBackgroundLocation(), isFalse);
    });

    test('shouldShowRationale is true only for a plain denial', () async {
      handler.statuses[Permission.locationWhenInUse] = PermissionStatus.denied;
      handler.statuses[Permission.locationAlways] =
          PermissionStatus.permanentlyDenied;
      final service = serviceOn();

      expect(
        await service.shouldShowRationale(AppPermission.locationWhenInUse),
        isTrue,
      );
      expect(
        await service.shouldShowRationale(AppPermission.locationAlways),
        isFalse,
      );
    });

    test('openAppSettings delegates to the plugin', () async {
      expect(await serviceOn().openAppSettings(), isTrue);
      expect(handler.settingsOpened, equals(1));
    });

    test('isLocationServiceEnabled delegates to geolocator', () async {
      geolocator.serviceEnabled = false;

      expect(await serviceOn().isLocationServiceEnabled(), isFalse);
    });

    test(
      'locationAccuracy reports the reduced accuracy geolocator gives',
      () async {
        // iOS 14+ "Precise Location" off, or Android 12+ coarse-only.
        geolocator.accuracy = LocationAccuracyStatus.reduced;

        expect(
          await serviceOn().locationAccuracy(),
          equals(LocationAccuracyStatus.reduced),
        );
      },
    );

    test(
      'locationAccuracy falls back to precise when the platform throws',
      () async {
        // Accuracy must never block the app: a platform that does not implement
        // the call is treated as precise rather than as a missing capability.
        geolocator.accuracyError = UnimplementedError('no getLocationAccuracy');

        expect(
          await serviceOn().locationAccuracy(),
          equals(LocationAccuracyStatus.precise),
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // requestPermission
  // ---------------------------------------------------------------------------

  group('PermissionHandlerService.requestPermission', () {
    test(
      'returns the granted result for a foreground location grant',
      () async {
        handler.requestResults[Permission.locationWhenInUse] =
            PermissionStatus.granted;

        final status = await serviceOn().requestPermission(
          AppPermission.locationWhenInUse,
        );

        expect(status.isGranted, isTrue);
        expect(handler.requested, equals([Permission.locationWhenInUse]));
      },
    );

    test('throws when the location service itself is off', () async {
      geolocator.serviceEnabled = false;

      await expectLater(
        serviceOn().requestPermission(AppPermission.locationWhenInUse),
        throwsA(isA<LocationServiceDisabledException>()),
      );
      expect(handler.requested, isEmpty);
    });

    test(
      'does not gate non-location permissions on the location service',
      () async {
        geolocator.serviceEnabled = false;
        handler.requestResults[Permission.activityRecognition] =
            PermissionStatus.granted;

        final status = await serviceOn().requestPermission(
          AppPermission.activityRecognition,
        );

        expect(status.isGranted, isTrue);
      },
    );

    test('rejects a duplicate in-flight request', () async {
      final gate = Completer<void>();
      handler.requestGate = gate.future;
      handler.requestResults[Permission.locationWhenInUse] =
          PermissionStatus.granted;
      final service = serviceOn();

      final first = service.requestPermission(AppPermission.locationWhenInUse);
      await pumpEventQueue();

      await expectLater(
        service.requestPermission(AppPermission.locationWhenInUse),
        throwsA(isA<PermissionRequestInProgressException>()),
      );

      gate.complete();
      expect((await first).isGranted, isTrue);
    });

    test('releases the in-progress lock after a failure', () async {
      geolocator.serviceEnabled = false;
      final service = serviceOn();

      await expectLater(
        service.requestPermission(AppPermission.locationWhenInUse),
        throwsA(isA<LocationServiceDisabledException>()),
      );

      // The same permission can be requested again: the guard was released.
      geolocator.serviceEnabled = true;
      handler.requestResults[Permission.locationWhenInUse] =
          PermissionStatus.granted;
      expect(
        (await service.requestPermission(AppPermission.locationWhenInUse))
            .isGranted,
        isTrue,
      );
    });

    test('throws on a permanently denied result', () async {
      handler.requestResults[Permission.activityRecognition] =
          PermissionStatus.permanentlyDenied;

      await expectLater(
        serviceOn().requestPermission(AppPermission.activityRecognition),
        throwsA(isA<PermissionPermanentlyDeniedException>()),
      );
    });

    test('only throws on a plain denial when asked to', () async {
      handler.requestResults[Permission.activityRecognition] =
          PermissionStatus.denied;
      final service = serviceOn();

      final quiet = await service.requestPermission(
        AppPermission.activityRecognition,
      );
      expect(quiet.isDenied, isTrue);

      await expectLater(
        service.requestPermission(
          AppPermission.activityRecognition,
          throwOnDenied: true,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });
  });

  group('PermissionHandlerService - background location flow', () {
    test('refuses background location without the foreground grant', () async {
      handler.statuses[Permission.locationWhenInUse] = PermissionStatus.denied;

      await expectLater(
        serviceOn().requestPermission(AppPermission.locationAlways),
        throwsA(
          isA<PermissionDeniedException>().having(
            (e) => e.permission,
            'permission',
            AppPermission.locationWhenInUse,
          ),
        ),
      );
      expect(handler.requested, isEmpty);
    });

    test('Android 11+ opens settings instead of prompting', () async {
      handler.statuses[Permission.locationWhenInUse] = PermissionStatus.granted;
      handler.statuses[Permission.locationAlways] = PermissionStatus.denied;

      final status = await serviceOn(platform: _android11)
          .requestPermission(AppPermission.locationAlways);

      expect(status.isGranted, isFalse);
      expect(handler.settingsOpened, equals(1));
      expect(handler.requested, isEmpty);
    });

    test('Android 11+ skips settings when it is already granted', () async {
      handler.statuses[Permission.locationWhenInUse] = PermissionStatus.granted;
      handler.statuses[Permission.locationAlways] = PermissionStatus.granted;
      handler.requestResults[Permission.locationAlways] =
          PermissionStatus.granted;

      final status = await serviceOn(platform: _android11)
          .requestPermission(AppPermission.locationAlways);

      expect(status.isGranted, isTrue);
      expect(handler.settingsOpened, equals(0));
      expect(handler.requested, equals([Permission.locationAlways]));
    });

    test('Android 10 prompts for background location directly', () async {
      handler.statuses[Permission.locationWhenInUse] = PermissionStatus.granted;
      handler.requestResults[Permission.locationAlways] =
          PermissionStatus.granted;

      final status = await serviceOn(platform: _android10)
          .requestPermission(AppPermission.locationAlways);

      expect(status.isGranted, isTrue);
      expect(handler.settingsOpened, equals(0));
      expect(handler.requested, equals([Permission.locationAlways]));
    });
  });

  group('PermissionHandlerService - notification flow', () {
    test('below Android 13 it reports granted without prompting', () async {
      final status = await serviceOn(platform: _android10)
          .requestPermission(AppPermission.notification);

      expect(status.isGranted, isTrue);
      expect(handler.requested, isEmpty);
    });

    test('on Android 13+ it prompts', () async {
      handler.requestResults[Permission.notification] =
          PermissionStatus.granted;

      final status = await serviceOn(platform: _android13)
          .requestPermission(AppPermission.notification);

      expect(status.isGranted, isTrue);
      expect(handler.requested, equals([Permission.notification]));
    });
  });

  group('PermissionHandlerService.requestPermissions', () {
    test('keeps going after one permission throws', () async {
      // locationAlways will throw (no foreground grant); activityRecognition
      // must still be requested, and the failed one falls back to its status.
      handler.statuses[Permission.locationWhenInUse] = PermissionStatus.denied;
      handler.statuses[Permission.locationAlways] =
          PermissionStatus.permanentlyDenied;
      handler.requestResults[Permission.activityRecognition] =
          PermissionStatus.granted;

      final results = await serviceOn().requestPermissions([
        AppPermission.locationAlways,
        AppPermission.activityRecognition,
      ]);

      expect(results, hasLength(2));
      expect(
        results[AppPermission.locationAlways]!.isPermanentlyDenied,
        isTrue,
      );
      expect(results[AppPermission.activityRecognition]!.isGranted, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Exception model (moved down; these test permission_exceptions.dart)
  // ---------------------------------------------------------------------------

  group('Permission exceptions', () {
    test('AppPermission enum has correct display names', () {
      expect(
        AppPermission.locationWhenInUse.displayName,
        equals('Location (While Using)'),
      );
      expect(
        AppPermission.locationAlways.displayName,
        equals('Background Location'),
      );
      expect(AppPermission.notification.displayName, equals('Notifications'));
      expect(
        AppPermission.activityRecognition.displayName,
        equals('Activity Recognition'),
      );
    });

    test('PermissionDeniedException has correct message', () {
      const exception = PermissionDeniedException(
        AppPermission.locationWhenInUse,
      );

      expect(
        exception.toString(),
        equals('Permission denied (Location (While Using))'),
      );
      expect(exception, isA<PermissionException>());
    });

    test('PermissionPermanentlyDeniedException has correct message', () {
      const exception = PermissionPermanentlyDeniedException(
        AppPermission.locationAlways,
      );

      expect(exception.toString(), contains('permanently denied'));
      expect(exception.toString(), contains('Background Location'));
      expect(exception, isA<PermissionException>());
    });

    test('PermissionRequestInProgressException has correct message', () {
      const exception = PermissionRequestInProgressException(
        AppPermission.notification,
      );

      expect(exception.toString(), contains('already in progress'));
      expect(exception, isA<PermissionException>());
    });

    test('LocationServiceDisabledException messages', () {
      expect(
        const LocationServiceDisabledException().toString(),
        contains('Location service is disabled'),
      );
      expect(
        const LocationServiceDisabledException('Custom message').toString(),
        equals('Custom message'),
      );
    });
  });
}

const _android10 = PlatformInfo(
  type: PlatformType.android,
  version: '10',
  apiLevel: 29,
  isPhysicalDevice: true,
);

const _android11 = PlatformInfo(
  type: PlatformType.android,
  version: '11',
  apiLevel: 30,
  isPhysicalDevice: true,
);

const _android13 = PlatformInfo(
  type: PlatformType.android,
  version: '13',
  apiLevel: 33,
  isPhysicalDevice: true,
);

class _FakePlatformInfoService extends PlatformInfoService {
  _FakePlatformInfoService(this._info);

  final PlatformInfo _info;

  @override
  Future<PlatformInfo> build() async => _info;
}

/// Stands in for the real `permission_handler` plugin implementation.
class _FakePermissionHandler extends PermissionHandlerPlatform {
  final statuses = <Permission, PermissionStatus>{};
  final requestResults = <Permission, PermissionStatus>{};

  final checked = <Permission>[];
  final requested = <Permission>[];
  int settingsOpened = 0;

  /// When set, `requestPermissions` waits on this before completing, so a
  /// second concurrent request can be observed.
  Future<void>? requestGate;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    checked.add(permission);
    return statuses[permission] ?? PermissionStatus.denied;
  }

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    requested.addAll(permissions);
    if (requestGate != null) await requestGate;
    return {
      for (final p in permissions)
        p: requestResults[p] ?? PermissionStatus.denied,
    };
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Future<bool> shouldShowRequestPermissionRationale(
    Permission permission,
  ) async => false;

  @override
  Future<ServiceStatus> checkServiceStatus(Permission permission) async =>
      ServiceStatus.enabled;
}

/// Only `isLocationServiceEnabled` is reached from this service.
class _FakeGeolocator extends GeolocatorPlatform {
  bool serviceEnabled = true;
  LocationAccuracyStatus accuracy = LocationAccuracyStatus.precise;
  Object? accuracyError;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async {
    final error = accuracyError;
    if (error != null) throw error;
    return accuracy;
  }
}
