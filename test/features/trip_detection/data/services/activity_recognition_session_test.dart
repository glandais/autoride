import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autoride/core/audit/audit_level.dart';
import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/core/audit/audit_sink.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/trip_detection/data/services/activity_recognition_session.dart';

// ===========================================================================
// T055. The OS classifiers are journalled and read by nothing. What is
// testable from Dart is the contract at the channel: which calls cross it,
// what the log says when no update will ever come, and that an unchanged
// verdict — which Android repeats every interval — is written once.
// ===========================================================================
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late _RecordingSink sink;
  late String? startAnswer;

  setUp(() {
    calls = <MethodCall>[];
    startAnswer = 'granted';
    sink = _RecordingSink();
    AuditLog.install(sink, level: AuditLogLevel.normal);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ActivityRecognitionSession.channel, (
          call,
        ) async {
          calls.add(call);
          return call.method == 'start' ? startAnswer : null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ActivityRecognitionSession.channel, null);
    debugDefaultTargetPlatformOverride = null;
    AuditLog.uninstall();
  });

  Future<ActivityRecognitionSession> session({
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(
      activityRecognitionSessionProvider.notifier,
    );
    await pumpEventQueue();
    return notifier;
  }

  Future<void> deliver(Map<String, Object?> activity) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          ActivityRecognitionSession.channel.name,
          ActivityRecognitionSession.channel.codec.encodeMethodCall(
            MethodCall('onActivity', activity),
          ),
          (_) {},
        );
  }

  List<String> methods() => calls.map((c) => c.method).toList();
  Iterable<Map<String, dynamic>> acts([String? a]) =>
      sink.fieldsOf('act').where((l) => a == null || l['a'] == a);

  group('ActivityRecognitionSession - starting', () {
    test('start crosses once, carrying the Android interval', () async {
      final subject = await session(platform: TargetPlatform.android);

      await subject.start();
      await subject.start();

      final starts = calls.where((c) => c.method == 'start').toList();
      expect(starts, hasLength(1));
      expect(
        (starts.single.arguments as Map)['intervalMs'],
        AppConstants.activityRecognitionInterval.inMilliseconds,
      );
    });

    test('the authorisation found is journalled', () async {
      final subject = await session();

      await subject.start();

      expect(acts('start').single['st'], 'granted');
    });

    test(
      'a missing grant says so, rather than leaving the log silent',
      () async {
        // A log with no `upd` line must say whether the device saw nothing or
        // was never allowed to look.
        startAnswer = 'notDetermined';
        final subject = await session();

        await subject.start();

        expect(acts('start').single['st'], 'notDetermined');
      },
    );

    test(
      'a grant given mid-session starts the updates there and then',
      () async {
        startAnswer = 'denied';
        final subject = await session();
        await subject.start();

        startAnswer = 'granted';
        await subject.permissionChanged();

        expect(methods().where((m) => m == 'start'), hasLength(2));
        expect(acts('start').last['st'], 'granted');
      },
    );

    test('a grant given with no session running starts nothing', () async {
      final subject = await session();

      await subject.permissionChanged();

      expect(calls, isEmpty);
    });
  });

  group('ActivityRecognitionSession - stopping', () {
    test('stop crosses and is journalled when updates were running', () async {
      final subject = await session();
      await subject.start();

      await subject.stop();

      expect(methods(), <String>['start', 'stop']);
      expect(acts('stop'), hasLength(1));
    });

    test('stopping a session that never got updates crosses nothing', () async {
      startAnswer = 'denied';
      final subject = await session();
      await subject.start();

      await subject.stop();

      expect(methods(), <String>['start']);
      expect(acts('stop'), isEmpty);
    });

    test('a stop that lands while start is in flight still wins', () async {
      final subject = await session();

      final starting = subject.start();
      await subject.stop();
      await starting;

      // The native side was granted and started; it must be told to stop.
      expect(methods().last, 'stop');
      expect(acts('start'), isEmpty);
    });
  });

  group('ActivityRecognitionSession - updates', () {
    test('an activity reaches the log with its fields', () async {
      final subject = await session();
      await subject.start();

      await deliver(<String, Object?>{
        'k': 'car',
        'o': <String>['still'],
        'cf': 'high',
        'at': 1791189000000,
      });

      final update = acts('upd').single;
      expect(update['k'], 'car');
      expect(update['o'], <String>['still']);
      expect(update['cf'], 'high');
      expect(update['at'], 1791189000000);
    });

    test('an unchanged verdict is written once', () async {
      final subject = await session(platform: TargetPlatform.android);
      await subject.start();

      for (final pc in <int>[80, 82, 79]) {
        await deliver(<String, Object?>{'k': 'bike', 'cf': 'high', 'pc': pc});
      }
      await deliver(<String, Object?>{'k': 'bike', 'cf': 'medium', 'pc': 60});
      await deliver(<String, Object?>{'k': 'walk', 'cf': 'medium', 'pc': 60});

      expect(acts('upd').map((l) => '${l['k']}/${l['cf']}'), <String>[
        'bike/high',
        'bike/medium',
        'walk/medium',
      ]);
    });

    test('a new session writes its first verdict even if unchanged', () async {
      final subject = await session();
      await subject.start();
      await deliver(<String, Object?>{'k': 'still', 'cf': 'high'});
      await subject.stop();

      await subject.start();
      await deliver(<String, Object?>{'k': 'still', 'cf': 'high'});

      expect(acts('upd'), hasLength(2));
    });
  });

  group('ActivityRecognitionSession - failures and platforms', () {
    test('nothing crosses the channel off iOS and Android', () async {
      final subject = await session(platform: TargetPlatform.macOS);

      await subject.start();
      await subject.stop();

      expect(calls, isEmpty);
    });

    test('a platform failure is journalled rather than swallowed', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ActivityRecognitionSession.channel, (
            call,
          ) async {
            throw PlatformException(code: 'request', message: 'boom');
          });
      final subject = await session(platform: TargetPlatform.android);

      await subject.start();

      final fail = acts('fail').single;
      expect(fail['m'], 'start');
      expect(fail['ex'], contains('boom'));
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
