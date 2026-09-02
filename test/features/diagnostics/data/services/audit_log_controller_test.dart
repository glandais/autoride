import 'package:autoride/core/audit/audit_level.dart';
import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/features/diagnostics/data/services/audit_database.dart';
import 'package:autoride/features/diagnostics/data/services/audit_log_controller.dart';
import 'package:autoride/features/diagnostics/data/services/sqlite_audit_sink.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';
import 'package:autoride/features/settings/domain/models/user_settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../helpers/test_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(AuditLog.uninstall);
  tearDown(AuditLog.uninstall);

  ProviderContainer containerWith(UserSettings settings) {
    // The real sink reaches for `getDatabasesPath()`, which needs a platform
    // channel; this one runs the production schema in memory.
    final sink = SqliteAuditSink(database: _InMemoryAuditDatabase());
    addTearDown(sink.close);

    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWithValue(settings),
        auditSinkProvider.overrideWithValue(sink),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('installs nothing while the setting is off', () {
    final container = containerWith(const UserSettings());

    final level = container.read(auditLogControllerProvider);

    expect(level, AuditLogLevel.off);
    expect(AuditLog.enabled, isFalse);
  });

  test('level is off when disabled, whatever verbosity is stored', () {
    final container = containerWith(
      const UserSettings(auditLogLevel: AuditLogLevel.verbose),
    );

    expect(container.read(auditLogControllerProvider), AuditLogLevel.off);
    expect(AuditLog.enabled, isFalse);
  });

  test('installs a sink and emits a header when turned on', () async {
    final container = containerWith(const UserSettings(auditLogEnabled: true));

    final level = container.read(auditLogControllerProvider);

    expect(level, AuditLogLevel.normal);
    expect(AuditLog.enabled, isTrue);
    expect(AuditLog.verbose, isFalse);

    // The header is critical, so it is already on its way to the database.
    final stats = await container
        .read(auditLogControllerProvider.notifier)
        .stats();
    expect(stats.eventCount, greaterThan(0));
  });

  test('verbose level switches on verbose emission', () {
    final container = containerWith(
      const UserSettings(
        auditLogEnabled: true,
        auditLogLevel: AuditLogLevel.verbose,
      ),
    );

    expect(container.read(auditLogControllerProvider), AuditLogLevel.verbose);
    expect(AuditLog.verbose, isTrue);
  });

  test('lifecycle events are recorded and paused forces a flush', () async {
    final container = containerWith(const UserSettings(auditLogEnabled: true));
    container.read(auditLogControllerProvider);
    final controller = container.read(auditLogControllerProvider.notifier);

    final before = (await controller.stats()).eventCount;
    await controller.onLifecycleState(AppLifecycleState.paused);

    expect((await controller.stats()).eventCount, greaterThan(before));
  });

  test('lifecycle events are ignored while the log is off', () async {
    final container = containerWith(const UserSettings());
    container.read(auditLogControllerProvider);
    final controller = container.read(auditLogControllerProvider.notifier);

    await controller.onLifecycleState(AppLifecycleState.paused);

    expect((await controller.stats()).eventCount, 0);
  });

  test('stats report nothing when the log has never been on', () async {
    final container = containerWith(const UserSettings());
    container.read(auditLogControllerProvider);

    final stats = await container
        .read(auditLogControllerProvider.notifier)
        .stats();

    expect(stats.eventCount, 0);
    expect(stats.level, AuditLogLevel.off);
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
    // sqflite_ffi shares one `:memory:` database across the process.
    await db.delete('audit_events');
    return db;
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> deleteAuditDatabase() async {
    await _db?.delete('audit_events');
  }
}
