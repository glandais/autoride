import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/diagnostics/data/services/audit_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../helpers/test_database.dart';

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
}
