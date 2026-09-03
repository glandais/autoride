import 'dart:async';

import 'package:autoride/core/audit/audit_event.dart';
import 'package:autoride/features/diagnostics/data/services/audit_database.dart';
import 'package:autoride/features/diagnostics/data/services/sqlite_audit_sink.dart';
import 'package:autoride/features/diagnostics/domain/models/capture_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../helpers/test_database.dart';

/// Capture retention (T034 §3.4): a corpus and a journal share one file and
/// nothing else.
///
/// The two failures this pins are the ones that would be invisible until a
/// device run: a journal bound deleting the middle of a labelled session (which
/// leaves data whose `lbl` line is gone — worse than no data, because it is
/// silently mislabelled by the session before it), and a capture session
/// pushing a whole day of journal out of its own 20 MB bound.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late _FakeAuditDatabase database;
  late DateTime clock;

  setUp(() {
    database = _FakeAuditDatabase();
    clock = DateTime(2026, 9, 3, 10);
  });

  SqliteAuditSink buildSink({
    int? maxBytes,
    int? maxEvents,
    Duration? retention,
    int? captureMaxBytes,
    Duration? captureRetention,
  }) {
    final sink = SqliteAuditSink(
      database: database,
      now: () => clock,
      startPeriodicTimer: (_, _) => _NoopTimer(),
      maxBytes: maxBytes,
      maxEvents: maxEvents,
      retention: retention,
      captureMaxBytes: captureMaxBytes,
      captureRetention: captureRetention,
      purgeChunkSize: 10,
    );
    addTearDown(sink.close);
    return sink;
  }

  /// Insert [count] rows straight into the table, bypassing the buffer: these
  /// tests are about what retention deletes, not about how a line gets there.
  Future<void> seed({
    required int lvl,
    required int count,
    int? session,
    DateTime? at,
    String padding = '',
  }) async {
    final db = await database.database;
    final t = (at ?? clock).millisecondsSinceEpoch;
    final batch = db.batch();
    for (var i = 0; i < count; i++) {
      batch.insert('audit_events', <String, Object?>{
        't': t + i,
        'type': lvl == 2 ? AuditEvent.rawMotion : AuditEvent.fix,
        'lvl': lvl,
        'line': '{"e":"x","p":"$padding"}',
        'sess': session,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> seedSession({
    required int id,
    required DateTime endedAt,
    DateTime? exportedAt,
    int rows = 10,
  }) async {
    final db = await database.database;
    await db.insert('capture_sessions', <String, Object?>{
      'id': id,
      'activity': CaptureActivity.bike.name,
      'started_at': id,
      'ended_at': endedAt.millisecondsSinceEpoch,
      'exported_at': exportedAt?.millisecondsSinceEpoch,
    });
    await seed(lvl: 2, count: rows, session: id, padding: 'x' * 200);
  }

  /// Seeded rows of one level, excluding the `aud` markers a purge writes
  /// about itself — those are lvl 0 by design (a capture purge has to be
  /// visible to a reader of the journal) and would otherwise read as journal
  /// rows that survived.
  Future<int> countAt(int lvl) async {
    final db = await database.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM audit_events WHERE lvl = ? AND type != ?',
      <Object?>[lvl, AuditEvent.audit],
    );
    return rows.first['n']! as int;
  }

  Future<List<int>> sessionIds() async {
    final db = await database.database;
    final rows = await db.query('capture_sessions', orderBy: 'started_at');
    return rows.map((row) => row['id']! as int).toList();
  }

  group('the two classes never delete each other', () {
    test('the journal row bound leaves every capture row alone', () async {
      final sink = buildSink(maxEvents: 5);
      await seed(lvl: 0, count: 40);
      await seedSession(id: 1, endedAt: clock, rows: 20);

      await sink.purge(await database.database);

      expect(await countAt(0), lessThanOrEqualTo(6));
      expect(await countAt(2), 20);
    });

    test('the journal age bound leaves every capture row alone', () async {
      final sink = buildSink(retention: const Duration(hours: 1));
      await seed(
        lvl: 0,
        count: 10,
        at: clock.subtract(const Duration(days: 2)),
      );
      // Older than the journal's bound and far inside capture's own.
      await seed(
        lvl: 2,
        count: 10,
        session: 1,
        at: clock.subtract(const Duration(days: 2)),
      );

      await sink.purge(await database.database);

      expect(await countAt(0), 0);
      expect(await countAt(2), 10);
    });

    test('a large corpus does not push the journal out of its bound', () async {
      // The defect this pins: with one shared byte measurement, 200 kB of
      // capture against a 50 kB journal bound made the journal delete itself
      // chunk by chunk, for ever, without the file shrinking.
      final sink = buildSink(maxBytes: 50 * 1024);
      await seed(lvl: 0, count: 20, padding: 'x' * 100);
      await seedSession(id: 1, endedAt: clock, rows: 400);

      await sink.purge(await database.database);

      expect(await countAt(0), 20, reason: 'the journal is inside its bound');
      expect(await countAt(2), 400);
    });

    test('the capture budget leaves the journal alone', () async {
      final sink = buildSink(captureMaxBytes: 1024);
      await seed(lvl: 0, count: 30);
      await seedSession(
        id: 1,
        endedAt: clock.subtract(const Duration(hours: 2)),
        rows: 40,
      );
      await seedSession(id: 2, endedAt: clock, rows: 40);

      await sink.purge(await database.database);

      expect(await countAt(0), 30);
      expect(await countAt(2), lessThan(80));
    });
  });

  group('capture deletion order', () {
    test('an exported session goes before an older unexported one', () async {
      final sink = buildSink(captureMaxBytes: 3 * 1024);
      await seedSession(
        id: 1,
        endedAt: clock.subtract(const Duration(hours: 5)),
        rows: 10,
      );
      await seedSession(
        id: 2,
        endedAt: clock.subtract(const Duration(hours: 1)),
        exportedAt: clock,
        rows: 10,
      );

      await sink.purge(await database.database);

      // Session 2 is newer, and goes first anyway: it exists in a file the
      // user already has, and session 1 exists nowhere else.
      expect(await sessionIds(), <int>[1]);
    });

    test('sessions go whole, never half', () async {
      final sink = buildSink(captureMaxBytes: 2 * 1024);
      await seedSession(
        id: 1,
        endedAt: clock.subtract(const Duration(hours: 5)),
        rows: 10,
      );
      await seedSession(id: 2, endedAt: clock, rows: 10);

      await sink.purge(await database.database);

      final db = await database.database;
      for (final id in await sessionIds()) {
        final rows = await db.query(
          'audit_events',
          where: 'sess = ?',
          whereArgs: <Object?>[id],
        );
        expect(rows, hasLength(10), reason: 'session $id was cut in half');
      }
    });

    test('an expired session is deleted with its rows', () async {
      final sink = buildSink(captureRetention: const Duration(days: 30));
      await seedSession(
        id: 1,
        endedAt: clock.subtract(const Duration(days: 40)),
        rows: 10,
      );
      await seedSession(id: 2, endedAt: clock, rows: 10);

      await sink.purge(await database.database);

      expect(await sessionIds(), <int>[2]);
      expect(await countAt(2), 10);
    });

    test('the session being recorded is the last thing touched', () async {
      final sink = buildSink(captureMaxBytes: 2 * 1024);
      await seedSession(
        id: 1,
        endedAt: clock.subtract(const Duration(hours: 5)),
        rows: 10,
      );
      // The live one: no `ended_at`, and the sink knows it is active.
      final db = await database.database;
      await db.insert('capture_sessions', <String, Object?>{
        'id': 2,
        'activity': CaptureActivity.car.name,
        'started_at': 2,
      });
      await seed(lvl: 2, count: 10, session: 2, padding: 'x' * 200);
      sink.activeCaptureSession = 2;

      await sink.purge(db);

      expect(
        await sessionIds(),
        contains(2),
        reason: 'the live session must survive while another can be dropped',
      );
    });
  });

  group('the purge says what it deleted', () {
    test('a lost capture session leaves an aud line behind it', () async {
      final sink = buildSink(captureMaxBytes: 1024);
      await seedSession(
        id: 1,
        endedAt: clock.subtract(const Duration(hours: 5)),
        rows: 40,
      );

      await sink.purge(await database.database);

      final db = await database.database;
      final markers = await db.query(
        'audit_events',
        where: 'type = ?',
        whereArgs: <Object?>[AuditEvent.audit],
      );
      expect(markers, isNotEmpty);
      expect(markers.last['line'], contains('"why":"capture"'));
    });
  });

  group('deleting the corpus', () {
    test('clearCapture keeps the journal', () async {
      final sink = buildSink();
      await seed(lvl: 0, count: 10);
      await seed(lvl: 1, count: 5, session: null);
      await seedSession(id: 1, endedAt: clock, rows: 20);

      final deleted = await sink.clearCapture();

      expect(deleted, 20);
      expect(await countAt(2), 0);
      expect(await countAt(0), 10);
      expect(await countAt(1), 5);
      expect(await sessionIds(), isEmpty);
    });
  });

  group('session bookkeeping', () {
    test(
      'begin then end records the span and frees it for retention',
      () async {
        final sink = buildSink();
        await sink.beginCaptureSession(id: 100, activity: 'bike');
        expect(sink.activeCaptureSession, 100);

        clock = clock.add(const Duration(minutes: 5));
        await sink.endCaptureSession(100);

        expect(sink.activeCaptureSession, isNull);
        final sessions = await sink.captureSessions();
        expect(sessions.single.activity, CaptureActivity.bike);
        expect(sessions.single.isRecording, isFalse);
        expect(sessions.single.isExported, isFalse);
      },
    );

    test('an export marks only the finished sessions', () async {
      final sink = buildSink();
      await sink.beginCaptureSession(id: 100, activity: 'bike');
      await sink.endCaptureSession(100);
      await sink.beginCaptureSession(id: 200, activity: 'car');

      await sink.markCaptureSessionsExported();

      final sessions = await sink.captureSessions();
      expect(sessions.firstWhere((s) => s.id == 100).isExported, isTrue);
      expect(
        sessions.firstWhere((s) => s.id == 200).isExported,
        isFalse,
        reason: 'a session still recording has not been exported in full',
      );
    });

    test('captureStats counts sessions, rows and what is unexported', () async {
      final sink = buildSink();
      await seedSession(id: 1, endedAt: clock, rows: 12);
      await seedSession(id: 2, endedAt: clock, exportedAt: clock, rows: 8);

      final stats = await sink.captureStats();

      expect(stats.sessionCount, 2);
      expect(stats.rowCount, 20);
      expect(stats.unexportedSessionCount, 1);
      expect(stats.sizeBytes, greaterThan(0));
    });
  });
}

/// [AuditDatabase] backed by an in-memory database built from the production
/// schema, so retention is exercised against the real DDL (L-014).
class _FakeAuditDatabase extends AuditDatabase {
  Database? _db;

  @override
  bool get isOpen => _db != null;

  @override
  Future<Database> get database async => _db ??= await openAuditDatabase();

  @override
  Future<Database> openAuditDatabase() async {
    final db = await createTestAuditDatabase();
    // sqflite_ffi hands the same `:memory:` database to every opener in the
    // process, so a previous test's rows would otherwise still be here.
    await db.delete('audit_events');
    await db.delete('capture_sessions');
    return db;
  }

  @override
  Future<void> close() async {}
}

class _NoopTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => false;

  @override
  int get tick => 0;
}
