import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/audit/audit_event.dart';
import '../../../../core/audit/audit_log.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/logger.dart';

part 'activity_recognition_session.g.dart';

const _logger = Logger('ActivityRecognitionSession');

/// Dart side of the OS activity classifiers (T055):
/// `ios/Runner/AutoRideActivityRecognition.swift` (CoreMotion) and
/// `android/…/ActivityRecognitionChannel.kt` (Play services).
///
/// Both platforms already run a classifier on the inertial unit that tells a
/// bicycle from a car or a walk. Read through a second app on the same phone,
/// over the 2026-10-09 log, it said cycling on every one of the twelve real
/// rides, automotive on both town drives and walking — almost nothing else —
/// on the seven walks History kept as rides: the separation speed could not
/// make (T053) and the start fit was never meant to (T054 §6).
///
/// **This class journals; it decides nothing.** Every activity becomes an
/// `act` line and goes no further. What the classifier may be trusted with is
/// to be decided on logs that carry it.
///
/// It runs for as long as automatic detection is listening, and never asks for
/// the permission itself: a session can start from a background relaunch,
/// where a prompt has no business appearing. Settings asks, then calls
/// [permissionChanged].
@Riverpod(keepAlive: true)
class ActivityRecognitionSession extends _$ActivityRecognitionSession {
  /// Shared with both native sides.
  static const MethodChannel channel = MethodChannel(
    'dev.glandais.autoride/activity',
  );

  /// A detection session wants updates.
  bool _wanted = false;

  /// The native side confirmed updates are running.
  bool _running = false;

  /// The last activity journalled, so an unchanged verdict is not repeated:
  /// Android reports every interval whether anything changed or not.
  String? _lastSignature;

  @override
  void build() {
    if (!supported) return;

    channel.setMethodCallHandler(_onNativeEvent);
    ref.onDispose(() => channel.setMethodCallHandler(null));
  }

  /// iOS and Android. `defaultTargetPlatform` rather than `Platform` so tests
  /// can drive the unsupported branch.
  static bool get supported =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  /// Ask for updates. Journals the authorisation it found, so a log with no
  /// `upd` line says whether that is a missing grant or a silent device.
  Future<void> start() async {
    if (!supported || _wanted) return;
    _wanted = true;
    await _subscribe();
  }

  /// End the updates with the detection session.
  Future<void> stop() async {
    if (!supported || !_wanted) return;
    _wanted = false;
    if (!_running) return;
    _running = false;
    await _invoke<void>('stop');
    AuditLog.emit(AuditEvent.activity, () => <String, Object?>{'a': 'stop'});
  }

  /// The user answered the permission prompt. A session that is already
  /// listening without updates gets them now rather than at the next start.
  Future<void> permissionChanged() async {
    if (!supported || !_wanted || _running) return;
    await _subscribe();
  }

  Future<void> _subscribe() async {
    _lastSignature = null;
    final status = await _invoke<String>('start', <String, Object?>{
      'intervalMs': AppConstants.activityRecognitionInterval.inMilliseconds,
    });
    // A stop that arrived while the platform call was in flight wins.
    if (!_wanted) {
      if (status == 'granted') await _invoke<void>('stop');
      return;
    }
    _running = status == 'granted';
    if (status == null) return; // a failure, already journalled
    AuditLog.emit(
      AuditEvent.activity,
      () => <String, Object?>{'a': 'start', 'st': status},
    );
  }

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e, stackTrace) {
      // Never fatal, never silent: "failed" and "never called" must not be the
      // same observation in the log (L-078).
      _logger.error('Activity recognition: $method failed', e, stackTrace);
      AuditLog.emit(
        AuditEvent.activity,
        () => <String, Object?>{'a': 'fail', 'm': method, 'ex': e.toString()},
        critical: true,
      );
      return null;
    } on MissingPluginException {
      // A build or a host without the native side — tests among them.
      return null;
    }
  }

  Future<void> _onNativeEvent(MethodCall call) async {
    if (call.method != 'onActivity') return;
    final arguments = call.arguments;
    if (arguments is! Map) return;

    final others = arguments['o'];
    final signature =
        '${arguments['k']}|${arguments['cf']}|'
        '${others is List ? others.join(',') : ''}';
    if (signature == _lastSignature) return;
    _lastSignature = signature;

    AuditLog.emit(
      AuditEvent.activity,
      () => <String, Object?>{
        'a': 'upd',
        for (final entry in arguments.entries) '${entry.key}': entry.value,
      },
    );
  }
}
