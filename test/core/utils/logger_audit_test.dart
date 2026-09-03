import 'dart:convert';

import 'package:autoride/core/audit/audit_level.dart';
import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/core/audit/audit_sink.dart';
import 'package:autoride/core/utils/logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(AuditLog.uninstall);
  tearDown(AuditLog.uninstall);

  test('records nothing while the audit log is off', () {
    const Logger('X').warning('No GPS fix for 612s');

    expect(AuditLog.enabled, isFalse);
  });

  test('mirrors a warning as a log event with its tag and level', () {
    final sink = _RecordingSink();
    AuditLog.install(sink, level: AuditLogLevel.normal);

    // The exact line item 10 of the device checklist tells the maintainer to
    // look for — invisible in a release build until this bridge existed.
    const Logger('TripDetectionCoordinator')
        .warning('No GPS fix for 612s (limit 600s) — stopping the trip');

    final decoded = jsonDecode(sink.lines.single) as Map<String, dynamic>;
    expect(decoded['e'], 'log');
    expect(decoded['lv'], 'w');
    expect(decoded['tag'], 'TripDetectionCoordinator');
    expect(decoded['m'], contains('stopping the trip'));
    expect(sink.criticals.single, isFalse);
  });

  test('an error is critical and carries the exception and top frames', () {
    final sink = _RecordingSink();
    AuditLog.install(sink, level: AuditLogLevel.normal);

    const Logger('Rec').error(
      'Failed to start trip recording',
      StateError('db closed'),
      StackTrace.fromString('#0 a\n#1 b\n#2 c\n#3 d\n#4 e'),
    );

    final decoded = jsonDecode(sink.lines.single) as Map<String, dynamic>;
    expect(decoded['e'], 'err');
    expect(decoded['ex'], contains('db closed'));
    expect(decoded['st'], '#0 a | #1 b | #2 c');
    expect(sink.criticals.single, isTrue);
  });
}

class _RecordingSink implements AuditSink {
  final List<String> lines = <String>[];
  final List<bool> criticals = <bool>[];

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
    criticals.add(critical);
  }

  @override
  Future<void> flush() async {}
}
