import 'dart:convert';
import 'dart:io';

import 'package:autoride/core/audit/audit_level.dart';
import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/features/diagnostics/data/services/audit_database.dart';
import 'package:autoride/features/diagnostics/data/services/audit_export_service.dart';
import 'package:autoride/features/diagnostics/data/services/audit_log_controller.dart';
import 'package:autoride/features/diagnostics/data/services/sqlite_audit_sink.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';
import 'package:autoride/features/settings/domain/models/user_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PackageInfo.setMockInitialValues(
      appName: 'AutoRide',
      packageName: 'io.github.glandais.autoride',
      version: '1.0.0',
      buildNumber: '6',
      buildSignature: '',
    );
  });

  setUp(() {
    AuditLog.uninstall();
    tempDirectory = Directory.systemTemp.createTempSync('audit_export');
    PathProviderPlatform.instance = _FakePathProvider(tempDirectory.path);
  });

  tearDown(() {
    AuditLog.uninstall();
    tempDirectory.deleteSync(recursive: true);
  });

  ProviderContainer containerWithLog() {
    final sink = SqliteAuditSink(database: _InMemoryAuditDatabase());
    addTearDown(sink.close);

    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWithValue(
          const UserSettings(
            auditLogEnabled: true,
            auditLogLevel: AuditLogLevel.verbose,
          ),
        ),
        auditSinkProvider.overrideWithValue(sink),
      ],
    );
    addTearDown(container.dispose);
    container.read(auditLogControllerProvider);
    return container;
  }

  Future<List<String>> exportedLines(
    ProviderContainer container, {
    DateTime? since,
  }) async {
    final file = await container
        .read(auditExportServiceProvider)
        .writeLogFile(since: since);

    final bytes = await file.readAsBytes();
    return const LineSplitter()
        .convert(utf8.decode(gzip.decode(bytes)))
        .where((line) => line.isNotEmpty)
        .toList();
  }

  test('the file is real gzip and the first line is the header', () async {
    final container = containerWithLog();

    final lines = await exportedLines(container);

    final header = jsonDecode(lines.first) as Map<String, dynamic>;
    expect(header['e'], 'hdr');
    expect(header['sv'], 1);
    expect(header['app'], '1.0.0+6');
    expect(header['tz'], matches(RegExp(r'^[+-]\d{2}:\d{2}$')));
  });

  test(
    'the header carries this build\'s thresholds, not the reader\'s',
    () async {
      final container = containerWithLog();

      final lines = await exportedLines(container);

      final header = jsonDecode(lines.first) as Map<String, dynamic>;
      final thresholds = header['k'] as Map<String, dynamic>;
      expect(thresholds['gpsLoss'], 600);
      expect(thresholds['conf'], 0.7);
      expect(thresholds['sdMax'], 0.8);
    },
  );

  test('every recorded event is exported, in order, one per line', () async {
    final container = containerWithLog();
    final controller = container.read(auditLogControllerProvider.notifier);

    for (var i = 0; i < 250; i++) {
      AuditLog.emit('fix', () => <String, Object?>{'n': i});
    }
    await controller.flush();

    final lines = await exportedLines(container);

    // The header, the controller's own session header, and the 250 events.
    expect(lines.length, greaterThanOrEqualTo(251));

    final fixes = lines
        .map((l) => jsonDecode(l) as Map<String, dynamic>)
        .where((m) => m['e'] == 'fix')
        .toList();
    expect(fixes, hasLength(250));
    expect(fixes.first['n'], 0);
    expect(fixes.last['n'], 249);
  });

  test('lines survive the round trip byte for byte', () async {
    final container = containerWithLog();
    final controller = container.read(auditLogControllerProvider.notifier);

    AuditLog.emit(
      'log',
      () => <String, Object?>{'m': 'Trip "42" arrêté — 8 km'},
    );
    await controller.flush();

    final lines = await exportedLines(container);

    final logLine = lines
        .map((l) => jsonDecode(l) as Map<String, dynamic>)
        .firstWhere((m) => m['e'] == 'log');
    expect(logLine['m'], 'Trip "42" arrêté — 8 km');
  });

  test('a since filter drops what precedes it', () async {
    final container = containerWithLog();
    final controller = container.read(auditLogControllerProvider.notifier);

    AuditLog.emit('fix', () => <String, Object?>{'n': 1});
    await controller.flush();

    final future = DateTime.now().add(const Duration(days: 1));
    final lines = await exportedLines(container, since: future);

    // Only the header, which is rebuilt at export time and always present.
    expect(lines, hasLength(1));
    expect((jsonDecode(lines.single) as Map<String, dynamic>)['e'], 'hdr');
    expect((jsonDecode(lines.single) as Map<String, dynamic>)['n'], 0);
  });

  test('the file name is stamped in local time, like the FIT export', () {
    final name = AuditExportService.fileNameFor(DateTime(2026, 9, 2, 7, 5));

    expect(name, 'autoride-audit-20260902-0705.ndjson.gz');
  });

  test('exporting a log that was never on fails rather than shipping an '
      'empty file', () async {
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWithValue(const UserSettings()),
      ],
    );
    addTearDown(container.dispose);
    container.read(auditLogControllerProvider);

    expect(
      () => container.read(auditExportServiceProvider).writeLogFile(),
      throwsStateError,
    );
  });
}

class _InMemoryAuditDatabase extends AuditDatabase {
  Database? _db;

  @override
  bool get isOpen => _db != null;

  @override
  Future<Database> get database async => _db ??= await openAuditDatabase();

  @override
  Future<Database> openAuditDatabase() async {
    final db = await createTestAuditDatabase();
    await db.delete('audit_events');
    return db;
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> deleteAuditDatabase() async => _db?.delete('audit_events');
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}
