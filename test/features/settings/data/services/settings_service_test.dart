import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/core/audit/audit_sink.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingAuditSink sink;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sink = _RecordingAuditSink();
    AuditLog.install(sink, verbose: false);
    addTearDown(AuditLog.uninstall);

    container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsServiceProvider.future);
  });

  SettingsService service() =>
      container.read(settingsServiceProvider.notifier);

  Iterable<Map<String, dynamic>> settingChanges(String key) => sink.lines
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .where((m) => m['e'] == 'set' && m['k'] == key);

  group('SettingsService - audit instrumentation', () {
    // The log is the only witness to its own configuration. Without these
    // lines an exported journal that simply stops is indistinguishable from
    // one killed with the process, which inverts checklist item 8.
    test('turning the diagnostic log off is declared before it stops', () async {
      await service().updatePartial((s) => s.copyWith(auditLogEnabled: true));
      await service().updatePartial((s) => s.copyWith(auditLogEnabled: false));

      final changes = settingChanges('auditLog').toList();
      expect(changes, hasLength(2));
      expect(changes.first['n'], isTrue);
      // R-16: this one was missing, so the log just ended.
      expect(changes.last['o'], isTrue);
      expect(changes.last['n'], isFalse);
    });

    test('a setting that did not change emits nothing', () async {
      await service().updatePartial((s) => s.copyWith(auditLogEnabled: false));

      expect(settingChanges('auditLog'), isEmpty);
    });

    test('the settings that change what the pipeline does are all covered',
        () async {
      final current = container.read(settingsServiceProvider).requireValue;
      await service().updateSettings(
        current.copyWith(
          auditLogEnabled: !current.auditLogEnabled,
          backgroundLocationEnabled: !current.backgroundLocationEnabled,
        ),
      );

      final keys = sink.lines
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .where((m) => m['e'] == 'set')
          .map((m) => m['k']);
      expect(keys, contains('auditLog'));
      expect(keys, contains('backgroundLocation'));
    });
  });
}

/// Collects audit lines and decodes them on demand.
class _RecordingAuditSink implements AuditSink {
  final List<String> lines = <String>[];

  @override
  void write(
    String line, {
    required int t,
    required String type,
    required int lvl,
    required bool critical,
  }) => lines.add(line);

  @override
  Future<void> flush() async {}
}
