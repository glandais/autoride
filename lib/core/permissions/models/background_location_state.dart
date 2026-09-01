import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:geolocator/geolocator.dart' show LocationAccuracyStatus;

import 'permission_status.dart';

part 'background_location_state.freezed.dart';

/// Why background trip detection cannot work right now.
///
/// Ordered by how much it hurts: without "Always" nothing runs in the
/// background at all, so a missing permission is reported even when the
/// accuracy is also reduced.
enum BackgroundLocationIssue {
  /// The OS did not grant "Always" / "Allow all the time".
  alwaysMissing,

  /// Granted, but only approximate location — iOS 14+ "Precise Location" off,
  /// or Android 12+ where only `ACCESS_COARSE_LOCATION` was granted. GPS points
  /// are then kilometres off and recorded trips are unusable.
  preciseMissing,
}

/// Everything the OS says about background location, in one value.
///
/// `permission_handler` ignores accuracy entirely: with "Always" but
/// approximate location it reports a plain "granted" while the trips the app
/// records are worthless. [accuracy] comes from geolocator's
/// `getLocationAccuracy()` and closes that gap.
@freezed
sealed class BackgroundLocationState with _$BackgroundLocationState {
  const BackgroundLocationState._();

  const factory BackgroundLocationState({
    required AppPermissionStatus permission,
    required LocationAccuracyStatus accuracy,
  }) = _BackgroundLocationState;
}

extension BackgroundLocationStateExtensions on BackgroundLocationState {
  /// The one thing to tell the user about, or `null` when all is well.
  ///
  /// A missing permission wins over a reduced accuracy: fixing the accuracy
  /// alone would still leave detection dead in the background.
  BackgroundLocationIssue? get issue {
    if (!permission.isGranted) return BackgroundLocationIssue.alwaysMissing;
    if (accuracy == LocationAccuracyStatus.reduced) {
      return BackgroundLocationIssue.preciseMissing;
    }
    return null;
  }

  /// True when background detection can actually record usable trips.
  bool get isReady => issue == null;
}
