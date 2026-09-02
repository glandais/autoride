import 'package:autoride/core/audit/audit_level.dart';
import 'package:autoride/features/diagnostics/data/services/audit_export_service.dart';
import 'package:autoride/features/diagnostics/domain/models/audit_log_stats.dart';
import 'package:autoride/features/diagnostics/presentation/widgets/audit_log_section.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';
import 'package:autoride/features/settings/domain/models/user_settings.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

import '../../../../helpers/widget/pump_app.dart';

void main() {
  late _SpyExportService exportService;
  late _FakeSettingsService settingsService;

  setUp(() {
    exportService = _SpyExportService();
    settingsService = _FakeSettingsService();
  });

  Future<void> pumpSection(
    WidgetTester tester, {
    bool enabled = true,
    AuditLogLevel level = AuditLogLevel.normal,
    AuditLogStats? stats,
  }) async {
    final settings = UserSettings(
      auditLogEnabled: enabled,
      auditLogLevel: level,
    );

    await pumpAppWidget(
      tester,
      // Wrapped in a Consumer that watches the settings, exactly as
      // SettingsScreen does: without a listener the AsyncNotifier is still
      // loading when the switch is tapped, and `updatePartial` no-ops.
      // The Scaffold is what a SnackBar needs somewhere above it, and the
      // Consumer watches the settings exactly as SettingsScreen does: without
      // a listener the AsyncNotifier is still loading when the switch is
      // tapped, and `updatePartial` no-ops.
      Scaffold(
        body: SingleChildScrollView(
          child: Consumer(
            builder: (context, ref, _) {
              ref.watch(settingsServiceProvider);
              return AuditLogSection(settings: settings);
            },
          ),
        ),
      ),
      overrides: <Override>[
        settingsServiceProvider.overrideWith(() => settingsService),
        auditExportServiceProvider.overrideWithValue(exportService),
        auditLogStatsProvider.overrideWith(
          (ref) async => stats ?? AuditLogStats.empty(level),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  group('the switch', () {
    testWidgets('hides the level, stats and actions while it is off', (
      tester,
    ) async {
      await pumpSection(tester, enabled: false);

      expect(find.text('Record a diagnostic log'), findsOneWidget);
      expect(find.text('Detail level'), findsNothing);
      expect(find.text('Export log…'), findsNothing);
      expect(find.text('Clear log'), findsNothing);
    });

    testWidgets('says up front that positions are recorded', (tester) async {
      await pumpSection(tester, enabled: false);

      // The user has to know what the log holds before turning it on, not
      // only at the moment of sharing.
      expect(find.textContaining('precise GPS positions'), findsOneWidget);
    });

    testWidgets('turning it on writes the setting', (tester) async {
      await pumpSection(tester, enabled: false);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(settingsService.saved.single.auditLogEnabled, isTrue);
    });

    testWidgets('shows the controls once it is on', (tester) async {
      await pumpSection(tester);

      expect(find.text('Detail level'), findsOneWidget);
      expect(find.text('Export log…'), findsOneWidget);
      expect(find.text('Clear log'), findsOneWidget);
    });
  });

  group('the stats row', () {
    testWidgets('says so plainly when nothing has been recorded', (
      tester,
    ) async {
      await pumpSection(tester);

      expect(find.text('Nothing recorded yet'), findsOneWidget);
    });

    testWidgets('reports the span actually covered, not the retention '
        'promise', (tester) async {
      await pumpSection(
        tester,
        stats: AuditLogStats(
          eventCount: 12431,
          sizeBytes: 1887436,
          oldestAt: DateTime(2026, 9, 1, 14, 2),
          newestAt: DateTime(2026, 9, 2, 8, 30),
          level: AuditLogLevel.normal,
        ),
      );

      expect(find.textContaining('12431 events'), findsOneWidget);
      expect(find.textContaining('1.8 MB'), findsOneWidget);
      expect(find.textContaining('since 01/09 14:02'), findsOneWidget);
    });
  });

  group('export', () {
    testWidgets('asks before anything leaves the device, and Cancel really '
        'cancels', (tester) async {
      await pumpSection(tester);

      await tester.tap(find.text('Export log…'));
      await tester.pumpAndSettle();

      expect(find.text('Share diagnostic log?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(exportService.shareCalls, 0);
    });

    testWidgets('shares once the warning is accepted', (tester) async {
      await pumpSection(tester);

      await tester.tap(find.text('Export log…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(exportService.shareCalls, 1);
    });

    testWidgets('a failure is reported instead of failing silently', (
      tester,
    ) async {
      exportService.failure = StateError('no log');
      await pumpSection(tester);

      await tester.tap(find.text('Export log…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to export'), findsOneWidget);
    });
  });

  group('clear', () {
    testWidgets('confirms before deleting', (tester) async {
      await pumpSection(tester);

      await tester.tap(find.text('Clear log'));
      await tester.pumpAndSettle();

      expect(find.text('Clear diagnostic log?'), findsOneWidget);
    });
  });
}

class _SpyExportService implements AuditExportService {
  int shareCalls = 0;
  Object? failure;

  @override
  Future<File> shareLog({Rect? sharePosition, DateTime? since}) async {
    if (failure != null) throw failure!;
    shareCalls++;
    return File('unused');
  }

  @override
  Future<File> writeLogFile({DateTime? since}) async => File('unused');
}

class _FakeSettingsService extends SettingsService {
  final List<UserSettings> saved = <UserSettings>[];

  @override
  Future<UserSettings> build() async => const UserSettings();

  @override
  Future<void> updateSettings(UserSettings settings) async {
    saved.add(settings);
    state = AsyncValue.data(settings);
  }
}
