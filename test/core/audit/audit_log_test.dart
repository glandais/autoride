import 'dart:convert';

import 'package:autoride/core/audit/audit_level.dart';
import 'package:autoride/core/audit/audit_event.dart';
import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/core/audit/audit_sink.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // AuditLog is deliberately global state (it has to be callable without a
  // Ref). Every test starts and ends with it uninstalled, or one test leaks
  // into the next.
  setUp(AuditLog.uninstall);
  tearDown(AuditLog.uninstall);

  group('when no sink is installed', () {
    test('emit is a no-op and does not build its fields', () {
      var built = 0;

      AuditLog.emit(AuditEvent.fix, () {
        built++;
        return {'lat': 1.0};
      });

      expect(AuditLog.enabled, isFalse);
      // The whole point of the closure: nothing is allocated or computed when
      // the log is off.
      expect(built, 0);
    });

    test('emitVerbose is a no-op and does not build its fields', () {
      var built = 0;

      AuditLog.emitVerbose(AuditEvent.window, () {
        built++;
        return {'sd': 0.4};
      });

      expect(built, 0);
    });
  });

  group('with a sink installed', () {
    late _RecordingSink sink;

    setUp(() {
      sink = _RecordingSink();
      AuditLog.install(sink, level: AuditLogLevel.normal);
    });

    test('writes t and e first so the line stays greppable', () {
      AuditLog.emit(
        AuditEvent.stateChange,
        () => {'f': 'idle', 'to': 'active'},
      );

      expect(sink.lines, hasLength(1));
      expect(sink.lines.single, startsWith('{"t":'));
      expect(sink.lines.single, contains('"e":"st"'));
      expect(
        sink.lines.single.indexOf('"e":"st"'),
        lessThan(sink.lines.single.indexOf('"f":"idle"')),
      );
    });

    test('emitVerbose is dropped at normal level', () {
      AuditLog.emitVerbose(AuditEvent.window, () => {'sd': 0.4});

      expect(sink.lines, isEmpty);
    });

    test('emitVerbose is recorded at verbose level, tagged lvl 1', () {
      AuditLog.install(sink, level: AuditLogLevel.verbose);

      AuditLog.emitVerbose(AuditEvent.window, () => {'sd': 0.4});

      expect(sink.lines, hasLength(1));
      expect(sink.levels.single, 1);
    });

    test('critical is propagated to the sink', () {
      AuditLog.emit(AuditEvent.trip, () => {'a': 'start'}, critical: true);
      AuditLog.emit(AuditEvent.fix, () => {'lat': 1.0});

      expect(sink.criticals, [true, false]);
    });

    test('t and type are handed to the sink alongside the line', () {
      final before = DateTime.now().millisecondsSinceEpoch;

      AuditLog.emit(AuditEvent.gate, () => {'a': 'open'});

      final after = DateTime.now().millisecondsSinceEpoch;
      expect(sink.types.single, 'gate');
      expect(sink.timestamps.single, inInclusiveRange(before, after));
      expect(
        jsonDecode(sink.lines.single),
        containsPair('t', sink.timestamps.single),
      );
    });

    test('a throwing field getter loses the line, not the caller', () {
      expect(
        () => AuditLog.emit(AuditEvent.fix, () => throw StateError('boom')),
        returnsNormally,
      );
      expect(sink.lines, isEmpty);
    });

    test('install replaces the previous sink instead of failing', () {
      final replacement = _RecordingSink();
      AuditLog.install(replacement, level: AuditLogLevel.verbose);

      AuditLog.emit(AuditEvent.fix, () => {'lat': 1.0});

      expect(sink.lines, isEmpty);
      expect(replacement.lines, hasLength(1));
      expect(AuditLog.verbose, isTrue);
    });

    test('uninstall stops recording', () {
      AuditLog.uninstall();

      AuditLog.emit(AuditEvent.fix, () => {'lat': 1.0});

      expect(AuditLog.enabled, isFalse);
      expect(sink.lines, isEmpty);
    });
  });
}

class _RecordingSink implements AuditSink {
  final List<String> lines = <String>[];
  final List<int> timestamps = <int>[];
  final List<String> types = <String>[];
  final List<int> levels = <int>[];
  final List<bool> criticals = <bool>[];
  int flushCount = 0;

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
    timestamps.add(t);
    types.add(type);
    levels.add(lvl);
    criticals.add(critical);
  }

  @override
  Future<void> flush() async => flushCount++;
}
