import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autoride/core/audit/audit_level.dart';
import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/core/audit/audit_sink.dart';
import 'package:autoride/features/trip_detection/data/services/ios_background_session.dart';

// ===========================================================================
// T046. The native side of this is the only thing that keeps an iOS process
// alive once the motion gate closes (L-084), and the only thing that can bring
// it back after a kill or a reboot — significant-change and visit monitoring
// are not exposed by geolocator. What is testable from Dart is the contract at
// the channel: which calls cross it, in what order, and that none of them
// cross on Android.
// ===========================================================================
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late _RecordingSink sink;
  String? launchReason;

  setUp(() {
    calls = <MethodCall>[];
    launchReason = 'normal';
    sink = _RecordingSink();
    AuditLog.install(sink, level: AuditLogLevel.verbose);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(IosBackgroundSession.channel, (call) async {
          calls.add(call);
          return call.method == 'consumeLaunchReason' ? launchReason : null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(IosBackgroundSession.channel, null);
    debugDefaultTargetPlatformOverride = null;
    AuditLog.uninstall();
  });

  /// Builds the notifier with the platform decided up front — `supported` is
  /// read in `build()`.
  Future<IosBackgroundSession> session({
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(iosBackgroundSessionProvider.notifier);
    await pumpEventQueue();
    return notifier;
  }

  List<String> methods() => calls.map((c) => c.method).toList();

  group('IosBackgroundSession - launch reason', () {
    test('the launch reason is asked for once, at build', () async {
      await session();

      expect(methods(), <String>['consumeLaunchReason']);
    });

    test('a background relaunch is journalled as such', () async {
      launchReason = 'location';
      await session();

      // This line is the only evidence in the whole log that iOS brought a
      // terminated process back for a significant-change or visit event. The
      // device-validation protocol greps for exactly it.
      final bootstrap = sink
          .fieldsOf('ios')
          .firstWhere((line) => line['a'] == 'bootstrap');
      expect(bootstrap['lr'], 'location');
    });

    test('a normal launch says so rather than staying silent', () async {
      await session();

      final bootstrap = sink
          .fieldsOf('ios')
          .firstWhere((line) => line['a'] == 'bootstrap');
      expect(bootstrap['lr'], 'normal');
    });
  });

  group('IosBackgroundSession - arming', () {
    test('arm crosses the channel once', () async {
      final subject = await session();

      await subject.arm();
      await subject.arm();

      expect(methods().where((m) => m == 'arm'), hasLength(1));
    });

    test(
      'disarm always crosses, so a stale registration can be cleared',
      () async {
        final subject = await session();
        await subject.arm();

        await subject.disarm();

        expect(methods(), contains('disarm'));
      },
    );

    test('arming again after a disarm works', () async {
      final subject = await session();
      await subject.arm();
      await subject.disarm();

      await subject.arm();

      expect(methods().where((m) => m == 'arm'), hasLength(2));
    });
  });

  group('IosBackgroundSession - keep-alive', () {
    test('a repeated value does not cross the channel', () async {
      final subject = await session();

      await subject.setKeepAlive(on: true);
      await subject.setKeepAlive(on: true);

      expect(methods().where((m) => m == 'setKeepAlive'), hasLength(1));
    });

    test('each flip crosses, carrying the value', () async {
      final subject = await session();

      await subject.setKeepAlive(on: true);
      await subject.setKeepAlive(on: false);

      final keepAlive = calls.where((c) => c.method == 'setKeepAlive');
      expect(keepAlive.map((c) => (c.arguments as Map)['on']), <bool>[
        true,
        false,
      ]);
    });

    test('disarming forgets the mirrored state', () async {
      final subject = await session();
      await subject.setKeepAlive(on: true);
      await subject.disarm();

      // Not deduplicated against the pre-disarm value: the native session is
      // gone, so "already on" is no longer true.
      await subject.setKeepAlive(on: true);

      expect(methods().where((m) => m == 'setKeepAlive'), hasLength(2));
    });
  });

  group('IosBackgroundSession - failures and platforms', () {
    test('nothing crosses the channel on Android', () async {
      final subject = await session(platform: TargetPlatform.android);

      await subject.arm();
      await subject.setKeepAlive(on: true);
      await subject.disarm();

      expect(calls, isEmpty);
    });

    test('a platform failure is journalled rather than swallowed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(IosBackgroundSession.channel, (call) async {
            calls.add(call);
            throw PlatformException(code: 'boom');
          });

      final subject = await session();
      await subject.arm();

      // L-078 cost a field session to diagnose precisely because a swallowed
      // exception made "failed" and "never called" the same observation.
      expect(
        sink.fieldsOf('ios').where((line) => line['a'] == 'fail'),
        isNotEmpty,
      );
    });

    test('a native event reaches the log and goes no further', () async {
      await session();

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            IosBackgroundSession.channel.name,
            IosBackgroundSession.channel.codec.encodeMethodCall(
              const MethodCall('onEvent', <String, Object?>{
                'a': 'coarse',
                'n': 1,
                'ac': 3000.0,
              }),
            ),
            (_) {},
          );

      // A 3 km fix is journalled as evidence the process is alive. It is never
      // a position: reaching `_lastLocation` or the pre-trip buffer would
      // poison the start confidence T048 has just made trustworthy.
      final coarse = sink
          .fieldsOf('ios')
          .firstWhere((line) => line['a'] == 'coarse');
      expect(coarse['ac'], 3000.0);
    });
  });
}

/// Collects audit lines and decodes them on demand.
class _RecordingSink implements AuditSink {
  final List<String> lines = <String>[];

  @override
  void write(
    String line, {
    required int t,
    required String type,
    required int lvl,
    required bool critical,
    int? session,
  }) => lines.add(line);

  @override
  Future<void> flush() async {}

  Iterable<Map<String, dynamic>> fieldsOf(String type) => lines
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .where((m) => m['e'] == type);
}
