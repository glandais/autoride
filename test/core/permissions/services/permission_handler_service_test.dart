import 'package:flutter_test/flutter_test.dart';
import 'package:autoride/core/permissions/exceptions/permission_exceptions.dart';

void main() {
  group('PermissionHandlerService', () {
    test('AppPermission enum has correct display names', () {
      expect(
        AppPermission.locationWhenInUse.displayName,
        equals('Location (While Using)'),
      );
      expect(
        AppPermission.locationAlways.displayName,
        equals('Background Location'),
      );
      expect(
        AppPermission.notification.displayName,
        equals('Notifications'),
      );
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
    });

    test('PermissionPermanentlyDeniedException has correct message', () {
      const exception = PermissionPermanentlyDeniedException(
        AppPermission.locationAlways,
      );

      expect(
        exception.toString(),
        contains('permanently denied'),
      );
      expect(
        exception.toString(),
        contains('Background Location'),
      );
    });

    test('PermissionRequestInProgressException has correct message', () {
      const exception = PermissionRequestInProgressException(
        AppPermission.notification,
      );

      expect(
        exception.toString(),
        contains('already in progress'),
      );
    });

    test('LocationServiceDisabledException has default message', () {
      const exception = LocationServiceDisabledException();

      expect(
        exception.toString(),
        contains('Location service is disabled'),
      );
    });

    test('LocationServiceDisabledException accepts custom message', () {
      const exception = LocationServiceDisabledException('Custom message');

      expect(exception.toString(), equals('Custom message'));
    });
  });

  group('PermissionException hierarchy', () {
    test('PermissionDeniedException is a PermissionException', () {
      const exception = PermissionDeniedException(
        AppPermission.locationWhenInUse,
      );

      expect(exception, isA<PermissionException>());
    });

    test('PermissionPermanentlyDeniedException is a PermissionException', () {
      const exception = PermissionPermanentlyDeniedException(
        AppPermission.locationAlways,
      );

      expect(exception, isA<PermissionException>());
    });

    test('PermissionRequestInProgressException is a PermissionException', () {
      const exception = PermissionRequestInProgressException(
        AppPermission.notification,
      );

      expect(exception, isA<PermissionException>());
    });
  });
}
