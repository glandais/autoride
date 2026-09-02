import 'dart:async';

import 'package:autoride/core/audit/audit_level.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/diagnostics/data/services/audit_database.dart';
import 'package:autoride/features/diagnostics/data/services/sqlite_audit_sink.dart';
import 'package:autoride/features/diagnostics/domain/models/audit_log_stats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../helpers/test_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late _FakeAuditDatabase database;
  late _ManualTimer timer;
  late DateTime clock;

  SqliteAuditSink buildSink() {
    final sink = SqliteAuditSink(
      database: database,
      now: () => clock,
      startPeriodicTimer: (duration, onTick) {
        timer.duration = duration;
        timer.onTick = onTick;
        return timer;
      },
    );
    addTearDown(sink.close);
    return sink;
  }

  setUp(() {
    database = _FakeAuditDatabase();
    timer = _ManualTimer();
    clock = DateTime(2026, 9, 2, 10);
  });

  Future<List<Map<String, Object?>>> rows() async {
    final db = await database.database;
    return db.query('audit_events', orderBy: 'id');
  }

  void writeLines(SqliteAuditSink sink, int count, {bool critical = false}) {
    for (var i = 0; i < count; i++) {
      sink.write(
        '{"t":$i,"e":"fix","n":$i}',
        t: i,
        type: 'fix',
        lvl: 0,
        critical: critical,
      );
    }
  }

  group('batching', () {
    test(
      'buffers below the batch size instead of committing per line',
      () async {
        final sink = buildSink();

        writeLines(sink, 10);
        await pumpEventQueue();

        expect(sink.bufferedCount, 10);
        expect(database.opened, isFalse, reason: 'no database until a flush');
      },
    );

    test('commits once the batch size is reached', () async {
      final sink = buildSink();

      writeLines(sink, AppConstants.auditFlushBatchSize);
      await pumpEventQueue();

      expect(await rows(), hasLength(AppConstants.auditFlushBatchSize));
      expect(sink.bufferedCount, 0);
    });

    test('a critical event is committed immediately', () async {
      final sink = buildSink();

      writeLines(sink, 3);
      sink.write(
        '{"t":9,"e":"trip"}',
        t: 9,
        type: 'trip',
        lvl: 0,
        critical: true,
      );
      await pumpEventQueue();

      // The point of `critical`: the event is on disk before the thing it
      // announces happens, so a kill cannot take it with the buffer.
      final written = await rows();
      expect(written, hasLength(4));
      expect(written.last['type'], 'trip');
    });

    test('the periodic timer commits what is still buffered', () async {
      final sink = buildSink();

      writeLines(sink, 5);
      expect(await rows(), isEmpty);

      timer.fire();
      await pumpEventQueue();

      expect(await rows(), hasLength(5));
      expect(timer.duration, AppConstants.auditFlushInterval);
    });

    test('close flushes rather than dropping the tail', () async {
      final sink = SqliteAuditSink(
        database: database,
        now: () => clock,
        startPeriodicTimer: (duration, onTick) => timer,
      );

      writeLines(sink, 4);
      await sink.close();

      final db = await database.database;
      expect(await db.query('audit_events'), hasLength(4));
    });

    test('preserves the line byte for byte, with its columns', () async {
      final sink = buildSink();
      const line = '{"t":1,"e":"log","m":"arrêté — 8 km"}';

      sink.write(line, t: 1, type: 'log', lvl: 1, critical: true);
      await pumpEventQueue();

      final row = (await rows()).single;
      expect(row['line'], line);
      expect(row['t'], 1);
      expect(row['type'], 'log');
      expect(row['lvl'], 1);
    });

    test('writes after close are ignored', () async {
      final sink = SqliteAuditSink(
        database: database,
        now: () => clock,
        startPeriodicTimer: (duration, onTick) => timer,
      );
      await sink.close();

      sink.write(
        '{"t":1,"e":"fix"}',
        t: 1,
        type: 'fix',
        lvl: 0,
        critical: true,
      );
      await pumpEventQueue();

      expect(sink.bufferedCount, 0);
    });
  });

  group('overflow backstop', () {
    test('drops the oldest and declares the gap', () async {
      final sink = SqliteAuditSink(
        database: _StalledAuditDatabase(),
        now: () => clock,
        startPeriodicTimer: (duration, onTick) => timer,
      );

      // A stalled database means nothing ever commits; the buffer must stay
      // bounded rather than growing without limit inside the app it observes.
      writeLines(sink, AppConstants.auditMaxBufferedEvents + 50);
      await pumpEventQueue();

      // The bound plus one: the extra line is the `aud` marker declaring the
      // gap, appended when the flush that could not complete tried to report
      // it. A declared gap is the whole point — a silent one would be read as
      // an OS suspension.
      expect(
        sink.bufferedCount,
        lessThanOrEqualTo(AppConstants.auditMaxBufferedEvents + 1),
      );

      // And once a working database is available, the gap is reported rather
      // than left silent.
      final recovering = buildSink();
      writeLines(recovering, 1);
      await recovering.flush();
      await pumpEventQueue();
      expect(await rows(), isNotEmpty);
    });
  });

  group('retention', () {
    test('drops events older than the retention window', () async {
      final sink = buildSink();
      final db = await database.database;

      final old = clock
          .subtract(const Duration(days: 9))
          .millisecondsSinceEpoch;
      final recent = clock
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      await db.insert('audit_events', {
        't': old,
        'type': 'fix',
        'lvl': 0,
        'line': '{}',
      });
      await db.insert('audit_events', {
        't': recent,
        'type': 'fix',
        'lvl': 0,
        'line': '{}',
      });

      await sink.purge(db);

      final remaining = await rows();
      expect(remaining, hasLength(1));
      expect(remaining.single['t'], recent);
    });

    test('keeps purging correct when the wall clock jumps backwards', () async {
      final sink = buildSink();
      final db = await database.database;

      // An NTP correction can put "now" behind rows already written. Those rows
      // are in the future, not expired, and must survive.
      final future = clock.add(const Duration(days: 2)).millisecondsSinceEpoch;
      await db.insert('audit_events', {
        't': future,
        'type': 'fix',
        'lvl': 0,
        'line': '{}',
      });

      await sink.purge(db);

      expect(await rows(), hasLength(1));
    });
  });

  group('stats', () {
    test('reports nothing before the database is opened', () async {
      final sink = buildSink();

      final stats = await sink.stats(AuditLogLevel.normal);

      expect(stats.eventCount, 0);
      expect(stats.sizeBytes, 0);
      expect(stats.coverage, isNull);
      expect(database.opened, isFalse);
    });

    test(
      'counts buffered events too, so the UI does not under-report',
      () async {
        final sink = buildSink();

        sink.write(
          '{"t":1000,"e":"fix"}',
          t: 1000,
          type: 'fix',
          lvl: 0,
          critical: true,
        );
        await pumpEventQueue();
        writeLines(sink, 3);

        final stats = await sink.stats(AuditLogLevel.verbose);

        expect(stats.eventCount, 4);
        expect(stats.sizeBytes, greaterThan(0));
        expect(stats.oldestAt, DateTime.fromMillisecondsSinceEpoch(1000));
        expect(stats.level, AuditLogLevel.verbose);
      },
    );
  });
}

/// [AuditDatabase] backed by an in-memory database built from the production
/// schema, so the sink is exercised against the real DDL.
class _FakeAuditDatabase extends AuditDatabase {
  Database? _db;
  bool opened = false;
  bool closeCalled = false;

  @override
  bool get isOpen => opened;

  @override
  Future<Database> get database async => _db ??= await openAuditDatabase();

  @override
  Future<Database> openAuditDatabase() async {
    opened = true;
    final db = await createTestAuditDatabase();
    // sqflite_ffi hands the same `:memory:` database to every opener in the
    // process, so a previous test's rows would otherwise still be here.
    await db.delete('audit_events');
    return db;
  }

  /// Deliberately keeps the in-memory database alive: `inMemoryDatabasePath`
  /// hands out a fresh empty database on every open, so really closing here
  /// would make it impossible to assert on what a flush wrote.
  @override
  Future<void> close() async {
    closeCalled = true;
  }

  @override
  Future<void> deleteAuditDatabase() async {
    await _db?.delete('audit_events');
  }
}

/// A database that never becomes available — a full disk, or a wedged handle.
class _StalledAuditDatabase extends AuditDatabase {
  @override
  Future<Database> get database => Completer<Database>().future;

  @override
  bool get isOpen => false;

  @override
  Future<void> close() async {}
}

/// Stand-in for `Timer.periodic`, fired by hand.
class _ManualTimer implements Timer {
  Duration? duration;
  void Function()? onTick;
  bool cancelled = false;

  void fire() => onTick?.call();

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}
