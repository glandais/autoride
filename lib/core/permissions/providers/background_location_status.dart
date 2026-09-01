import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:geolocator/geolocator.dart' show LocationAccuracyStatus;

import '../exceptions/permission_exceptions.dart';
import '../models/background_location_state.dart';
import '../services/permission_handler_service.dart';

part 'background_location_status.g.dart';

/// The *real* background-location capability, as the OS reports it.
///
/// Distinct from the `backgroundLocationEnabled` user setting, which is only a
/// stored preference: on iOS the user can pick "While Using" instead of
/// "Always" (and iOS offers the upgrade prompt only once per install), and on
/// Android 11+ "Allow all the time" can only be chosen in system settings. In
/// both cases the app keeps running but automatic detection cannot work with
/// the app in the background, and nothing used to tell the user.
///
/// On iOS, `permission_handler` reports `locationAlways` as granted only for
/// CoreLocation's "Always"; "While Using" maps to permanently denied. On
/// Android it is granted only with `ACCESS_BACKGROUND_LOCATION`.
///
/// The permission alone is not the whole story: `permission_handler` ignores
/// location *accuracy*, so "Always" with iOS 14+ "Precise Location" off (or
/// Android 12+ coarse-only) reads as granted while the recorded points are
/// kilometres off. The accuracy is therefore read from geolocator as well —
/// only when the permission is granted, since a missing permission is the
/// issue to report anyway and asking the OS then buys nothing.
///
/// Kept alive for the app's lifetime and re-read on app resume (the root
/// widget calls [refresh]), since the user changes it in system settings with
/// the app backgrounded. Callers that request the permission themselves
/// (onboarding, the settings toggle) call [refresh] afterwards.
@Riverpod(keepAlive: true)
class BackgroundLocationStatus extends _$BackgroundLocationStatus {
  @override
  Future<BackgroundLocationState> build() async {
    final service = ref.read(permissionHandlerServiceProvider.notifier);
    final permission = await service.checkPermission(
      AppPermission.locationAlways,
    );

    final accuracy = permission.isGranted
        ? await service.locationAccuracy()
        : LocationAccuracyStatus.precise;

    return BackgroundLocationState(permission: permission, accuracy: accuracy);
  }

  /// Re-read the permission and accuracy from the OS.
  void refresh() {
    if (!ref.mounted) return;
    ref.invalidateSelf();
  }
}
