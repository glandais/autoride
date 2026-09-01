import 'package:autoride/core/permissions/exceptions/permission_exceptions.dart';
import 'package:autoride/core/permissions/models/permission_status.dart';
import 'package:autoride/core/permissions/services/permission_handler_service.dart';

/// Scripted answers for [FakePermissionHandlerService].
///
/// Lives outside the notifier so a test can flip an answer between rebuilds
/// (the way the OS does after the user grants a permission in settings) and
/// still read the call log afterwards.
class PermissionScript {
  PermissionScript({
    Map<AppPermission, bool>? requestGrants,
    Map<AppPermission, bool>? checkGrants,
    Set<AppPermission>? permanentlyDenied,
  })  : requestGrants = requestGrants ?? {},
        checkGrants = checkGrants ?? {},
        permanentlyDenied = permanentlyDenied ?? {};

  /// Result returned by `requestPermission` per permission (default: denied).
  final Map<AppPermission, bool> requestGrants;

  /// Result returned by `checkPermission` per permission.
  ///
  /// Falls back to whatever the last request returned, so a granted request is
  /// visible to the follow-up check the provider does for background location.
  final Map<AppPermission, bool> checkGrants;

  /// Permissions whose request throws [PermissionPermanentlyDeniedException].
  final Set<AppPermission> permanentlyDenied;

  final List<AppPermission> requested = [];
  final List<AppPermission> checked = [];
  int settingsOpened = 0;

  bool wasRequested(AppPermission permission) => requested.contains(permission);
}

/// Permission service double: no platform channels, fully scripted.
///
/// Subclassing the real notifier (rather than mocking the plugin) is what lets
/// the widget tests assert on *navigation and state* instead of platform calls.
class FakePermissionHandlerService extends PermissionHandlerService {
  FakePermissionHandlerService(this.script);

  final PermissionScript script;

  @override
  Future<void> build() async {}

  AppPermissionStatus _status(AppPermission permission, bool granted) {
    return AppPermissionStatus(
      permission: permission,
      isGranted: granted,
      isDenied: !granted,
      isPermanentlyDenied: false,
      isRestricted: false,
      isLimited: false,
    );
  }

  @override
  Future<AppPermissionStatus> checkPermission(AppPermission permission) async {
    script.checked.add(permission);
    final granted = script.checkGrants[permission] ??
        script.requestGrants[permission] ??
        false;
    return _status(permission, granted);
  }

  @override
  Future<AppPermissionStatus> requestPermission(
    AppPermission permission, {
    bool throwOnDenied = false,
  }) async {
    script.requested.add(permission);

    if (script.permanentlyDenied.contains(permission)) {
      throw PermissionPermanentlyDeniedException(permission);
    }

    final granted = script.requestGrants[permission] ?? false;
    // A granted request is what a later check should see.
    script.checkGrants[permission] = granted;
    return _status(permission, granted);
  }

  @override
  Future<bool> openAppSettings() async {
    script.settingsOpened++;
    return true;
  }
}
