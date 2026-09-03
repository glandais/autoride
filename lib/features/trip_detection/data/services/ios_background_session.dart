import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/audit/audit_event.dart';
import '../../../../core/audit/audit_log.dart';
import '../../../../core/utils/logger.dart';

part 'ios_background_session.g.dart';

const _logger = Logger('IosBackgroundSession');

/// Dart side of `ios/Runner/AutoRideBackgroundSession.swift` (T046).
///
/// Two things Dart cannot do for itself on iOS, and one of them decides whether
/// the app works at all:
///
///   * **Staying alive while idle.** The GPS gate is motion-driven (audit #3),
///     which on Android is fine — the foreground service holds the process
///     regardless (L-067). On iOS the location session *is* what keeps the
///     process scheduled, so closing the gate suspended the app 40 s later and
///     the sensors that should have re-opened it stopped arriving (L-084). The
///     native side runs a coarse 3 km session for exactly as long as the gate
///     is closed.
///   * **Coming back from the dead.** Significant-change and visit monitoring
///     are the only APIs that relaunch a terminated app, and they survive a
///     reboot. `geolocator` exposes neither.
///
/// Everything here is a no-op off iOS, so callers never branch on the platform.
///
/// The channel is one-way per call and deliberately fire-and-forget: none of
/// these operations has a result worth waiting on, and blocking the coordinator
/// on a platform round-trip during a departure is a worse failure than a
/// missing log line.
@Riverpod(keepAlive: true)
class IosBackgroundSession extends _$IosBackgroundSession {
  /// Shared with `AutoRideBackgroundSession.channelName`.
  static const MethodChannel channel = MethodChannel(
    'dev.glandais.autoride/ios_background',
  );

  /// Mirrors the native session so a redundant call never crosses the channel.
  /// The native side guards too; this keeps the audit log free of no-op lines.
  bool? _keepAlive;
  bool _armed = false;

  @override
  void build() {
    if (!supported) return;

    channel.setMethodCallHandler(_onNativeEvent);
    ref.onDispose(() => channel.setMethodCallHandler(null));

    // Asked once per process. On a background relaunch this is the only line
    // in the log that says the launch was not the user's doing.
    unawaited(_reportLaunchReason());
  }

  /// False everywhere but iOS. `defaultTargetPlatform` rather than
  /// `Platform.isIOS` so widget tests can drive both branches.
  static bool get supported => defaultTargetPlatform == TargetPlatform.iOS;

  /// Arm significant-change + visit monitoring, and persist the flag the native
  /// side reads at launch. Called when automatic detection starts listening.
  Future<void> arm() async {
    if (!supported || _armed) return;
    _armed = true;
    await _invoke('arm');
  }

  /// Disarm it. This is what makes iOS stop relaunching the app once the user
  /// turns automatic detection off.
  Future<void> disarm() async {
    if (!supported) return;
    _armed = false;
    _keepAlive = null;
    await _invoke('disarm');
  }

  /// [on] is true exactly while the Dart GPS gate is closed: the coarse native
  /// session and geolocator's fine one are mutually exclusive, so a 3 km fix
  /// can never reach the detection pipeline.
  Future<void> setKeepAlive({required bool on}) async {
    if (!supported || _keepAlive == on) return;
    _keepAlive = on;
    await _invoke('setKeepAlive', <String, Object?>{'on': on});
  }

  Future<void> _reportLaunchReason() async {
    final reason = await _invokeWithResult<String>('consumeLaunchReason');
    AuditLog.emit(
      AuditEvent.iosBackground,
      () => <String, Object?>{'a': 'bootstrap', 'lr': reason ?? 'unknown'},
      critical: true,
    );
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    await _invokeWithResult<void>(method, arguments);
  }

  Future<T?> _invokeWithResult<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e, stackTrace) {
      // Never fatal: detection and recording go on without the native session,
      // exactly as they do on a platform that has none. But a swallowed failure
      // must still leave a line, or "failed" and "never called" become the same
      // observation — the mistake L-078 cost a whole field session to find.
      _logger.error('iOS background session: $method failed', e, stackTrace);
      AuditLog.emit(
        AuditEvent.iosBackground,
        () => <String, Object?>{'a': 'fail', 'm': method, 'ex': e.toString()},
        critical: true,
      );
      return null;
    } on MissingPluginException {
      // A build without the native file. Silent by design: it is a
      // configuration fact, not a runtime failure, and it repeats on every call.
      return null;
    }
  }

  /// Coarse fixes, visits and monitoring changes pushed by the native side.
  /// They are journalled and go no further — see [AuditEvent.iosBackground].
  Future<void> _onNativeEvent(MethodCall call) async {
    if (call.method != 'onEvent') return;
    final arguments = call.arguments;
    if (arguments is! Map) return;

    AuditLog.emit(
      AuditEvent.iosBackground,
      () => <String, Object?>{
        for (final entry in arguments.entries) '${entry.key}': entry.value,
      },
    );
  }
}
