import 'dart:async';

import 'dart:convert';
import 'dart:io';

import 'package:autoride/core/audit/audit_event.dart';
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
  late int timersCreated;

  Timer installTimer(Duration duration, void Function() onTick) {
    timersCreated++;
    timer
      ..duration = duration
      ..onTick = onTick
      ..cancelled = false;
    return timer;
  }

  SqliteAuditSink buildSink({AuditDatabase? on}) {
    final sink = SqliteAuditSink(
      database: on ?? database,
      now: () => clock,
      startPeriodicTimer: installTimer,
    );
    addTearDown(sink.close);
    return sink;
  }

  setUp(() {
    database = _FakeAuditDatabase();
    timer = _ManualTimer();
    timersCreated = 0;
    clock = DateTime(2026, 9, 2, 10);
  });

  Future<List<Map<String, Object?>>> rows() async {
    final db = await database.database;
    return db.query('audit_events', orderBy: 'id');
  }

  /// The stored lines, decoded — the sink's contract is the *content* of the
  /// NDJSON, not just the row count.
  Future<List<Map<String, Object?>>> decodedLines() async {
    return (await rows())
        .map((row) => jsonDecode(row['line']! as String) as Map<String, Object?>)
        .toList();
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
        startPeriodicTimer: installTimer,
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
    });

    test('writes an aud overflow marker naming how many lines went', () async {
      final gate = _GatedAuditDatabase(database);
      final sink = buildSink(on: gate);

      // Block the first flush so the buffer really overruns, then let it
      // through: the marker is written by the *next* flush, with the count.
      gate.block();
      writeLines(sink, AppConstants.auditMaxBufferedEvents + 50);
      await pumpEventQueue();
      gate.release();
      await sink.flush();
      await sink.flush();

      final markers = (await decodedLines())
          .where((line) => line['e'] == AuditEvent.audit)
          .toList();

      expect(markers, hasLength(1));
      expect(markers.single['a'], 'overflow');
      // Not just "some number": an under-reported gap reads as a shorter
      // suspension than actually happened.
      expect(markers.single['n'], greaterThanOrEqualTo(50));
    });

    test(
      'a trim during an in-flight flush never discards uncommitted lines',
      () async {
        final gate = _GatedAuditDatabase(database);
        final sink = buildSink(on: gate);

        // 100 lines, committed by the critical one — but the commit is held
        // open, so `pending` is those 100 and the buffer keeps growing.
        gate.block();
        writeLines(sink, 99);
        sink.write(
          '{"t":99,"e":"fix","n":99}',
          t: 99,
          type: 'fix',
          lvl: 0,
          critical: true,
        );
        await pumpEventQueue();

        // Overrun the bound by 10 while that flush is stuck. The backstop
        // trims 10 lines off the front — all of them inside `pending`.
        for (var i = 100; i < AppConstants.auditMaxBufferedEvents + 10; i++) {
          sink.write(
            '{"t":$i,"e":"fix","n":$i}',
            t: i,
            type: 'fix',
            lvl: 0,
            critical: false,
          );
        }
        expect(sink.bufferedCount, AppConstants.auditMaxBufferedEvents);

        gate.release();
        await sink.flush();
        await sink.flush();

        // Removing "the first `pending.length`" would have thrown away lines
        // 100–109, which were never committed and are not in the declared gap.
        final written = (await decodedLines())
            .where((line) => line['e'] == 'fix')
            .map((line) => line['n'] as int)
            .toSet();
        expect(written, hasLength(AppConstants.auditMaxBufferedEvents + 10));
        for (var i = 0; i < AppConstants.auditMaxBufferedEvents + 10; i++) {
          expect(written, contains(i), reason: 'line $i was lost');
        }
      },
    );
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

  group('flush chaining', () {
    test(
      'a critical line arriving mid-commit is flushed, not left for the timer',
      () async {
        final gate = _GatedAuditDatabase(database);
        final sink = buildSink(on: gate);

        // A batch is in flight and stuck on the database.
        gate.block();
        writeLines(sink, AppConstants.auditFlushBatchSize);
        await pumpEventQueue();

        // The critical line is *not* in that batch's `pending` copy, so
        // skipping the flush because one is in flight would leave it in memory
        // until the 5 s timer — the window a kill takes it in.
        sink.write(
          '{"t":9,"e":"trip"}',
          t: 9,
          type: 'trip',
          lvl: 0,
          critical: true,
        );
        gate.release();
        // Generously pumped rather than `await sink.flush()`: an explicit
        // flush here would commit the line even with the defect, and prove
        // nothing. The timer is never fired.
        await pumpEventQueue(times: 500);

        expect(
          (await rows()).map((row) => row['type']),
          contains('trip'),
          reason: 'the timer was never fired; only a chained flush can do this',
        );
      },
    );

    test('a flush during a flush keeps write order and loses nothing', () async {
      final gate = _GatedAuditDatabase(database);
      final sink = buildSink(on: gate);

      gate.block();
      writeLines(sink, AppConstants.auditFlushBatchSize);
      await pumpEventQueue();
      for (var i = 0; i < 20; i++) {
        sink.write(
          '{"t":${1000 + i},"e":"fix","n":${1000 + i}}',
          t: 1000 + i,
          type: 'fix',
          lvl: 0,
          critical: true,
        );
      }
      gate.release();
      await sink.flush();
      await pumpEventQueue();

      final written = (await decodedLines())
          .map((line) => line['n'] as int)
          .toList();
      expect(written, hasLength(AppConstants.auditFlushBatchSize + 20));
      expect(written, orderedEquals(<int>[
        for (var i = 0; i < AppConstants.auditFlushBatchSize; i++) i,
        for (var i = 0; i < 20; i++) 1000 + i,
      ]));
      expect(sink.bufferedCount, 0);
    });

    test('a failed batch is retried from the buffer, not lost', () async {
      final flaky = _FlakyAuditDatabase(database);
      final sink = buildSink(on: flaky);

      writeLines(sink, 3);
      sink.write(
        '{"t":9,"e":"trip"}',
        t: 9,
        type: 'trip',
        lvl: 0,
        critical: true,
      );
      await pumpEventQueue();

      // The commit failed, so nothing was written and nothing was dropped.
      expect(await rows(), isEmpty);
      expect(sink.bufferedCount, 4);

      timer.fire();
      await pumpEventQueue();

      expect(await rows(), hasLength(4));
      expect(sink.bufferedCount, 0);
      expect(flaky.failures, 0);
    });
  });

  group('clear', () {
    test('a flush spanning a clear does not resurrect the erased lines', () async {
      final gate = _GatedAuditDatabase(database);
      final sink = buildSink(on: gate);

      gate.block();
      writeLines(sink, AppConstants.auditFlushBatchSize);
      await pumpEventQueue();

      // "Clear log" while the batch is committing. Without a generation check
      // the flush would reopen the database and insert the batch it just
      // erased, so the user's delete would silently not happen.
      await sink.clear();
      gate.release();
      await pumpEventQueue();

      expect(await rows(), isEmpty);
      expect(sink.bufferedCount, 0);
    });

    test('lines written after a clear still land', () async {
      final sink = buildSink();

      writeLines(sink, 3);
      await sink.clear();
      sink.write(
        '{"t":9,"e":"trip"}',
        t: 9,
        type: 'trip',
        lvl: 0,
        critical: true,
      );
      await pumpEventQueue();

      expect(await rows(), hasLength(1));
    });
  });

  group('the periodic timer', () {
    test('is cancelled once the buffer drains, and recreated lazily', () async {
      final sink = buildSink();

      writeLines(sink, 5);
      expect(timersCreated, 1);
      expect(timer.cancelled, isFalse);

      await sink.flush();

      // A log that has been turned off keeps its sink (so the recording is
      // still exportable); it must not also keep a 5 s wakeup for the rest of
      // the process in the app whose whole thesis is battery.
      expect(sink.bufferedCount, 0);
      expect(timer.cancelled, isTrue);

      writeLines(sink, 1);
      expect(timersCreated, 2);
      expect(timer.cancelled, isFalse);
    });
  });

  group('retention bounds', () {
    // File-backed: `page_count` on `:memory:` does not respond to
    // `incremental_vacuum`, which is precisely why the byte bound could be
    // broken for a whole branch without a test noticing.
    late Directory directory;
    late AuditDatabase auditDatabase;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('autoride_audit_sink');
      auditDatabase = AuditDatabase(directory: directory.path);
    });

    tearDown(() async {
      await auditDatabase.close();
      if (directory.existsSync()) await directory.delete(recursive: true);
    });

    test('the byte bound shrinks the file without emptying the table', () async {
      // Bounds injected so the test needs kilobytes rather than 20 MB; the
      // production defaults are untouched.
      final sink = SqliteAuditSink(
        database: auditDatabase,
        now: () => clock,
        startPeriodicTimer: installTimer,
        maxBytes: 256 * 1024,
        purgeChunkSize: 200,
      );
      addTearDown(sink.close);

      final db = await auditDatabase.database;
      final padding = 'x' * 400;
      final batch = db.batch();
      for (var i = 0; i < 3000; i++) {
        batch.insert('audit_events', <String, Object?>{
          't': clock.millisecondsSinceEpoch - i,
          'type': 'fix',
          'lvl': 0,
          'line': '{"t":$i,"e":"fix","p":"$padding"}',
        });
      }
      await batch.commit(noResult: true);

      Future<int> sizeBytes() async {
        final pages = await db.rawQuery('PRAGMA page_count');
        final size = await db.rawQuery('PRAGMA page_size');
        return (pages.first.values.first! as int) *
            (size.first.values.first! as int);
      }

      expect(await sizeBytes(), greaterThan(256 * 1024));

      await sink.purge(db);

      // The whole point: the file really got smaller, and the journal is still
      // a journal. With `auto_vacuum` inert the loop deletes chunk after chunk
      // against a size that never moves and ends with an empty table.
      expect(await sizeBytes(), lessThanOrEqualTo(256 * 1024));
      final remaining = await db.query('audit_events');
      expect(remaining, isNotEmpty);
      expect(remaining.length, lessThan(3000));
    });
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

/// Wraps another [AuditDatabase] and holds `database` open on demand, so a
/// test can put a flush mid-commit and then act while it is stuck there.
class _GatedAuditDatabase extends AuditDatabase {
  _GatedAuditDatabase(this._delegate);

  final AuditDatabase _delegate;
  Completer<void>? _gate;

  void block() => _gate = Completer<void>();

  void release() {
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  bool get isOpen => _delegate.isOpen;

  @override
  Future<Database> get database async {
    final gate = _gate;
    if (gate != null) await gate.future;
    return _delegate.database;
  }

  @override
  Future<void> close() => _delegate.close();

  @override
  Future<void> deleteAuditDatabase() => _delegate.deleteAuditDatabase();
}

/// Fails the first commit — a momentarily locked database — then works.
class _FlakyAuditDatabase extends AuditDatabase {
  _FlakyAuditDatabase(this._delegate);

  final AuditDatabase _delegate;
  int failures = 1;

  @override
  bool get isOpen => _delegate.isOpen;

  @override
  Future<Database> get database async {
    if (failures > 0) {
      failures--;
      throw StateError('database is locked');
    }
    return _delegate.database;
  }

  @override
  Future<void> close() => _delegate.close();

  @override
  Future<void> deleteAuditDatabase() => _delegate.deleteAuditDatabase();
}
