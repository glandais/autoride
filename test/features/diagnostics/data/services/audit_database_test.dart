import 'dart:io';

import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/diagnostics/data/services/audit_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../helpers/test_database.dart';

String jsonPadding() {
  final padding = 'x' * 400;
  return '{"t":1,"e":"fix","p":"$padding"}';
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('schema', () {
    late Database db;

    setUp(() async {
      db = await createTestAuditDatabase();
      addTearDown(db.close);
    });

    test('creates audit_events with the columns retention needs', () async {
      final columns = await db.rawQuery('PRAGMA table_info(audit_events)');
      final names = columns.map((c) => c['name'] as String).toList();

      expect(names, containsAll(<String>['id', 't', 'type', 'lvl', 'line']));
    });

    test('indexes t, because the wall clock can go backwards', () async {
      final indexes = await db.rawQuery('PRAGMA index_list(audit_events)');
      final names = indexes.map((i) => i['name'] as String).toList();

      expect(names, contains('idx_audit_t'));
    });

    test(
      'does not index type — ~30 values and no query that needs it',
      () async {
        final indexes = await db.rawQuery('PRAGMA index_list(audit_events)');
        final names = indexes.map((i) => i['name'] as String).toList();

        expect(names, isNot(contains('idx_audit_type')));
      },
    );

    test('stores and returns a line byte for byte', () async {
      const line = '{"t":1,"e":"log","m":"Trip \\"42\\" arrêté — 8 km"}';

      await db.insert('audit_events', <String, Object?>{
        't': 1,
        'type': 'log',
        'lvl': 0,
        'line': line,
      });

      final rows = await db.query('audit_events');
      expect(rows.single['line'], line);
    });

    test('runs at the version the app ships', () async {
      final version = await db.getVersion();

      expect(version, AppConstants.auditDatabaseVersion);
    });
  });

  group('AuditDatabase', () {
    test('reports closed before anything opens it', () {
      // A user who never turns the log on must never get a database file.
      expect(AuditDatabase().isOpen, isFalse);
    });
  });

  // File-backed on purpose: both pragmas under test are inert on `:memory:`,
  // which is exactly why the in-memory seam let the pragma order regress.
  group('pragmas on a real file', () {
    late Directory directory;
    late AuditDatabase auditDatabase;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('autoride_audit_db');
      auditDatabase = AuditDatabase(directory: directory.path);
    });

    tearDown(() async {
      await auditDatabase.close();
      if (directory.existsSync()) await directory.delete(recursive: true);
    });

    test('auto_vacuum is INCREMENTAL, so the byte bound can shrink the file', () async {
      final db = await auditDatabase.database;

      final mode = await db.rawQuery('PRAGMA auto_vacuum');

      // 2 = INCREMENTAL. It reads 0 if the pragma is issued after anything has
      // written a page — `journal_mode = WAL` does — and 0 makes
      // `incremental_vacuum` a silent no-op, which turns the sink's byte bound
      // into a loop that deletes the whole journal.
      expect(mode.first.values.first, 2);
    });

    test('journal_mode is still WAL', () async {
      final db = await auditDatabase.database;

      final journal = await db.rawQuery('PRAGMA journal_mode');

      expect(journal.first.values.first, 'wal');
    });

    test('incremental_vacuum really returns pages after a delete', () async {
      final db = await auditDatabase.database;
      final line = jsonPadding();
      final batch = db.batch();
      for (var i = 0; i < 2000; i++) {
        batch.insert('audit_events', <String, Object?>{
          't': i,
          'type': 'fix',
          'lvl': 0,
          'line': line,
        });
      }
      await batch.commit(noResult: true);

      Future<int> pageCount() async {
        final rows = await db.rawQuery('PRAGMA page_count');
        return rows.first.values.first! as int;
      }

      final before = await pageCount();
      await db.delete('audit_events');
      await db.rawQuery('PRAGMA incremental_vacuum(1024)');

      expect(await pageCount(), lessThan(before));
    });
  });
}
