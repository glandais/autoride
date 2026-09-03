import 'dart:convert';

import 'package:autoride/core/audit/audit_event.dart';
import 'package:autoride/core/audit/audit_level.dart';
import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/core/audit/audit_sink.dart';
import 'package:flutter_test/flutter_test.dart';

/// The T034 capture axis: it is a second dimension, not a third level.
///
/// The matrix below is the whole point of the design. Capture has to survive a
/// journal that is off (a rider recording a car journey with diagnostics off)
/// and stay out of a journal that is on at verbose (a battery measurement must
/// not silently be paying for 8 MB/h of raw arrays).
void main() {
  late _RecordingSink sink;

  setUp(() => sink = _RecordingSink());
  tearDown(AuditLog.uninstall);

  group('the level/capture matrix', () {
    test('capture off, journal off: nothing is installed at all', () {
      expect(AuditLog.enabled, isFalse);
      expect(AuditLog.captureEnabled, isFalse);
      expect(AuditLog.installed, isFalse);

      AuditLog.emitCapture(AuditEvent.rawMotion, () => <String, Object?>{});
      expect(sink.lines, isEmpty);
    });

    test('capture on, journal off: only capture lines are written', () {
      AuditLog.install(sink, level: AuditLogLevel.off, capture: true);
      AuditLog.setCapture(capture: true, session: 42);

      AuditLog.emit(AuditEvent.fix, () => <String, Object?>{'lat': 1});
      AuditLog.emitVerbose(
        AuditEvent.sensors,
        () => <String, Object?>{'am': 9},
      );
      AuditLog.emitCapture(
        AuditEvent.rawMotion,
        () => <String, Object?>{'n': 1},
      );

      expect(AuditLog.enabled, isFalse);
      expect(AuditLog.verbose, isFalse);
      expect(AuditLog.captureEnabled, isTrue);
      expect(sink.types, <String>[AuditEvent.rawMotion]);
    });

    test('capture off, journal verbose: no capture line is written', () {
      AuditLog.install(sink, level: AuditLogLevel.verbose);

      AuditLog.emit(AuditEvent.fix, () => <String, Object?>{'lat': 1});
      AuditLog.emitVerbose(
        AuditEvent.sensors,
        () => <String, Object?>{'am': 9},
      );
      AuditLog.emitCapture(
        AuditEvent.rawMotion,
        () => <String, Object?>{'n': 1},
      );

      expect(sink.types, <String>[AuditEvent.fix, AuditEvent.sensors]);
    });

    test('both on: each line carries its own level', () {
      AuditLog.install(sink, level: AuditLogLevel.normal, capture: true);
      AuditLog.setCapture(capture: true, session: 7);

      AuditLog.emit(AuditEvent.fix, () => <String, Object?>{'lat': 1});
      AuditLog.emitVerbose(
        AuditEvent.sensors,
        () => <String, Object?>{'am': 9},
      );
      AuditLog.emitCapture(
        AuditEvent.rawMotion,
        () => <String, Object?>{'n': 1},
      );

      expect(sink.levels, <int>[0, 2]);
    });

    test('emitAlways survives a journal that is off, emit does not', () {
      AuditLog.install(sink, level: AuditLogLevel.off, capture: true);

      AuditLog.emit(AuditEvent.header, () => <String, Object?>{'sv': 2});
      expect(sink.lines, isEmpty);

      AuditLog.emitAlways(AuditEvent.header, () => <String, Object?>{'sv': 2});
      expect(sink.types, <String>[AuditEvent.header]);
      expect(sink.levels, <int>[0]);
    });
  });

  group('capture session stamping', () {
    test('every capture row carries the session id', () {
      AuditLog.install(sink, level: AuditLogLevel.off, capture: true);
      AuditLog.setCapture(capture: true, session: 1756900000000);

      AuditLog.emitCapture(
        AuditEvent.rawMotion,
        () => <String, Object?>{'n': 1},
      );

      expect(sink.sessions, <int?>[1756900000000]);
    });

    test('journal rows carry none, so retention can tell them apart', () {
      AuditLog.install(sink, level: AuditLogLevel.normal, capture: true);
      AuditLog.setCapture(capture: true, session: 5);

      AuditLog.emit(AuditEvent.fix, () => <String, Object?>{'lat': 1});

      expect(sink.sessions, <int?>[null]);
    });

    test('turning capture off clears the session', () {
      AuditLog.install(sink, level: AuditLogLevel.normal, capture: true);
      AuditLog.setCapture(capture: true, session: 5);
      AuditLog.setCapture(capture: false);

      expect(AuditLog.captureSession, isNull);
      AuditLog.emitCapture(AuditEvent.rawMotion, () => <String, Object?>{});
      expect(sink.lines, isEmpty);
    });
  });

  group('array encoding', () {
    test('a raw line round-trips its six axes at full length', () {
      AuditLog.install(sink, level: AuditLogLevel.off, capture: true);
      AuditLog.setCapture(capture: true, session: 1);

      final ax = List<double>.generate(50, (i) => i * 0.001);
      AuditLog.emitCapture(
        AuditEvent.rawMotion,
        () => <String, Object?>{'hz': 50, 'n': ax.length, 'ax': ax},
      );

      final line = jsonDecode(sink.lines.single) as Map<String, Object?>;
      expect(line['e'], AuditEvent.rawMotion);
      expect(line['n'], 50);
      expect((line['ax']! as List).length, 50);
    });

    test('elements are rounded like every other double, not stringified', () {
      AuditLog.install(sink, level: AuditLogLevel.off, capture: true);

      AuditLog.emitCapture(
        AuditEvent.rawMotion,
        () => <String, Object?>{
          'ax': <double>[1.23456789, 2.0, -0.0004],
        },
      );

      final line = jsonDecode(sink.lines.single) as Map<String, Object?>;
      // Three decimals, and a whole value as an int — the same contract every
      // scalar field has, so a consumer never has to special-case the arrays.
      expect(line['ax'], <Object>[1.235, 2, -0.0]);
    });

    test('a non-finite sample is dropped rather than costing the line', () {
      AuditLog.install(sink, level: AuditLogLevel.off, capture: true);

      AuditLog.emitCapture(
        AuditEvent.rawMotion,
        () => <String, Object?>{
          'ax': <double>[1.0, double.nan, 3.0],
        },
      );

      final line = jsonDecode(sink.lines.single) as Map<String, Object?>;
      expect(line['ax'], <Object?>[1, null, 3]);
    });
  });
}

class _RecordingSink implements AuditSink {
  final List<String> lines = <String>[];
  final List<String> types = <String>[];
  final List<int> levels = <int>[];
  final List<int?> sessions = <int?>[];

  @override
  void write(
    String line, {
    required int t,
    required String type,
    required int lvl,
    required bool critical,
    int? session,
  }) {
    lines.add(line);
    types.add(type);
    levels.add(lvl);
    sessions.add(session);
  }

  @override
  Future<void> flush() async {}
}
