import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/trip_detection/data/services/database_service.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';

/// These tests drive the **production** [DatabaseService]: the file-backed
/// `initDatabase()` and its real `onCreate` / `onUpgrade` / `onConfigure`
/// callbacks. Nothing here re-declares the schema, so DDL drift between what
/// ships and what is asserted is impossible (L-014).
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseService service;
  late Database db;

  setUp(() async {
    service = DatabaseService();
    // Start from a clean file: the handle is a static singleton on the class.
    await service.close();
    await service.deleteDatabase();
    db = await service.database;
  });

  tearDown(() async {
    await service.close();
    await service.deleteDatabase();
  });

  group('DatabaseService.initDatabase', () {
    test('opens the database at the configured version', () async {
      expect(db.isOpen, isTrue);
      expect(await db.getVersion(), equals(AppConstants.databaseVersion));
    });

    test('caches the handle (singleton)', () async {
      final again = await service.database;
      expect(identical(again, db), isTrue);

      // A second instance shares the same static handle.
      final other = await DatabaseService().database;
      expect(identical(other, db), isTrue);
    });

    test('close() releases the handle and a later get reopens', () async {
      await service.close();
      expect(db.isOpen, isFalse);

      final reopened = await service.database;
      expect(reopened.isOpen, isTrue);
      expect(identical(reopened, db), isFalse);
      db = reopened;
    });

    test('deleteDatabase() drops the file so onCreate runs again', () async {
      await db.insert('trips', _tripMap());
      expect(await _countTrips(db), equals(1));

      await service.close();
      await service.deleteDatabase();

      db = await service.database;
      expect(await _countTrips(db), equals(0));
    });
  });

  group('DatabaseService schema (production onCreate)', () {
    test('creates the trips table with the shipped columns', () async {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='trips'",
      );
      expect(tables, isNotEmpty);

      final columns = await db.rawQuery('PRAGMA table_info(trips)');
      final names = columns.map((c) => c['name'] as String).toSet();
      expect(
        names,
        equals({
          'id',
          'start_time',
          'end_time',
          'distance',
          'duration',
          'avg_speed',
          'max_speed',
          'detected_activity',
          'confidence_score',
          'user_confirmed',
          'status',
          'pause_duration',
          'suspected_vehicle',
        }),
      );

      // NOT NULL constraints real writes depend on.
      final notNull = {
        for (final c in columns) c['name'] as String: c['notnull'] == 1,
      };
      expect(notNull['start_time'], isTrue);
      expect(notNull['end_time'], isTrue);
      expect(notNull['distance'], isTrue);
      expect(notNull['duration'], isTrue);
      expect(notNull['detected_activity'], isTrue);
      expect(notNull['confidence_score'], isTrue);
      expect(notNull['avg_speed'], isFalse);
      expect(notNull['max_speed'], isFalse);
      expect(notNull['status'], isTrue);
      expect(notNull['pause_duration'], isTrue);
      expect(notNull['suspected_vehicle'], isTrue);

      // A row written without a status is a finished trip, so history keeps
      // showing it after the upgrade.
      final defaults = {
        for (final c in columns) c['name'] as String: c['dflt_value'],
      };
      expect(defaults['status'], equals("'${TripStatus.completed.name}'"));
      // A trip written before pauses were persisted reports no stops, not a
      // wrong number (L-073).
      expect(defaults['pause_duration'], equals('0'));
      // A trip written before the flag existed was never judged, and reads as
      // unflagged rather than as flagged-false-on-purpose (L-106).
      expect(defaults['suspected_vehicle'], equals('0'));
    });

    test('creates the route_points table with the shipped columns', () async {
      final columns = await db.rawQuery('PRAGMA table_info(route_points)');
      final names = columns.map((c) => c['name'] as String).toSet();
      expect(
        names,
        equals({
          'id',
          'trip_id',
          'latitude',
          'longitude',
          'altitude',
          'timestamp',
          'accuracy',
          'speed',
        }),
      );
    });

    test('creates every index the queries rely on', () async {
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      );
      final indexNames = indexes.map((e) => e['name'] as String).toList();

      expect(indexNames, contains('idx_trip_start_time'));
      expect(indexNames, contains('idx_trip_end_time'));
      expect(indexNames, contains('idx_route_points_trip_id'));
      expect(indexNames, contains('idx_route_points_timestamp'));
      expect(indexNames, contains('idx_trip_status'));
    });

    test('declares the route_points -> trips foreign key', () async {
      final fks = await db.rawQuery('PRAGMA foreign_key_list(route_points)');
      expect(fks, hasLength(1));
      expect(fks.first['table'], equals('trips'));
      expect(fks.first['from'], equals('trip_id'));
      expect(fks.first['to'], equals('id'));
      expect(fks.first['on_delete'], equals('CASCADE'));
    });

    test('enables foreign keys via onConfigure', () async {
      final result = await db.rawQuery('PRAGMA foreign_keys');
      expect(result.first['foreign_keys'], equals(1));
    });

    test('round-trips a Trip through the production schema', () async {
      final trip = Trip(
        startTime: DateTime.now().subtract(const Duration(hours: 1)),
        endTime: DateTime.now(),
        distance: 5000.0,
        duration: 3600,
        detectedActivity: ActivityType.cycling,
        confidenceScore: 0.92,
        avgSpeed: 18.0,
        maxSpeed: 25.0,
        userConfirmed: false,
      );

      final tripId = await db.insert('trips', trip.toMap());
      expect(tripId, greaterThan(0));

      final result = await db.query(
        'trips',
        where: 'id = ?',
        whereArgs: [tripId],
      );
      expect(result, hasLength(1));
      expect(result.first['distance'], equals(5000.0));
      expect(result.first['detected_activity'], equals('cycling'));
    });

    test('round-trips a RoutePoint through the production schema', () async {
      final tripId = await db.insert('trips', _tripMap());

      final point = RoutePoint(
        tripId: tripId,
        latitude: 48.8566,
        longitude: 2.3522,
        timestamp: DateTime.now(),
        altitude: 35.0,
        accuracy: 5.0,
        speed: 5.0,
      );

      final pointId = await db.insert('route_points', point.toMap());
      expect(pointId, greaterThan(0));

      final result = await db.query(
        'route_points',
        where: 'trip_id = ?',
        whereArgs: [tripId],
      );
      expect(result, hasLength(1));
      expect(result.first['latitude'], equals(48.8566));
      expect(result.first['longitude'], equals(2.3522));
    });

    test('cascade-deletes route points when their trip is deleted', () async {
      final tripId = await db.insert('trips', _tripMap());
      await db.insert(
        'route_points',
        RoutePoint(
          tripId: tripId,
          latitude: 48.8566,
          longitude: 2.3522,
          timestamp: DateTime.now(),
        ).toMap(),
      );

      expect(
        await db.query(
          'route_points',
          where: 'trip_id = ?',
          whereArgs: [tripId],
        ),
        hasLength(1),
      );

      await db.delete('trips', where: 'id = ?', whereArgs: [tripId]);

      expect(
        await db.query(
          'route_points',
          where: 'trip_id = ?',
          whereArgs: [tripId],
        ),
        isEmpty,
      );
    });

    test('rejects an orphan route point (FK enforced at runtime)', () async {
      await expectLater(
        db.insert(
          'route_points',
          RoutePoint(
            tripId: 999999,
            latitude: 48.8566,
            longitude: 2.3522,
            timestamp: DateTime.now(),
          ).toMap(),
        ),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('DatabaseService.onUpgrade', () {
    /// Builds the v1 schema by hand — the shipped `onCreate` now emits v2, so
    /// this is the only way to have a real pre-migration database to upgrade.
    /// It is a verbatim copy of the v1 DDL as of `c08734d`.
    Future<Database> openV1Database() async {
      return databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE trips (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                start_time INTEGER NOT NULL,
                end_time INTEGER NOT NULL,
                distance REAL NOT NULL,
                duration INTEGER NOT NULL,
                avg_speed REAL,
                max_speed REAL,
                detected_activity TEXT NOT NULL,
                confidence_score REAL NOT NULL,
                user_confirmed INTEGER DEFAULT 0
              )
            ''');
            await db.execute('''
              CREATE TABLE route_points (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                trip_id INTEGER NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                altitude REAL,
                timestamp INTEGER NOT NULL,
                accuracy REAL,
                speed REAL,
                FOREIGN KEY (trip_id) REFERENCES trips(id) ON DELETE CASCADE
              )
            ''');
          },
          onConfigure: service.onConfigure,
        ),
      );
    }

    test('the shipped schema version is 4', () {
      expect(AppConstants.databaseVersion, equals(4));
    });

    test(
      'v1 -> v2 adds status and backfills existing rows as completed',
      () async {
        final legacy = await openV1Database();
        addTearDown(legacy.close);

        // A trip written before the column existed: the user already sees it.
        final legacyId = await legacy.insert('trips', _tripMap());

        final before = await legacy.rawQuery('PRAGMA table_info(trips)');
        expect(
          before.map((c) => c['name']),
          isNot(contains('status')),
          reason: 'precondition: the v1 schema has no status column',
        );

        await service.onUpgrade(legacy, 1, AppConstants.databaseVersion);

        final after = await legacy.rawQuery('PRAGMA table_info(trips)');
        expect(after.map((c) => c['name']), contains('status'));
        expect(after, hasLength(13));

        final rows = await legacy.query(
          'trips',
          where: 'id = ?',
          whereArgs: [legacyId],
        );
        expect(rows, hasLength(1));
        expect(rows.first['status'], equals(TripStatus.completed.name));
        expect(
          Trip.fromMap(rows.first, const []).status,
          equals(TripStatus.completed),
          reason: 'a migrated row must read back as a finished trip',
        );

        // And the filter index history queries rely on came with it.
        final indexes = await legacy.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index'",
        );
        expect(indexes.map((e) => e['name']), contains('idx_trip_status'));
      },
    );

    test('is a no-op on an already-migrated database', () async {
      final tripId = await db.insert('trips', _tripMap());

      await service.onUpgrade(
        db,
        AppConstants.databaseVersion,
        AppConstants.databaseVersion,
      );

      final rows = await db.query(
        'trips',
        where: 'id = ?',
        whereArgs: [tripId],
      );
      expect(rows, hasLength(1));

      final columns = await db.rawQuery('PRAGMA table_info(trips)');
      expect(columns, hasLength(13));
    });

    /// Builds the v2 schema by hand, for the same reason `openV1Database`
    /// exists: the shipped `onCreate` now emits v4. Verbatim copy of the v2
    /// DDL as of `4559820`.
    Future<Database> openV2Database() async {
      return databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE trips (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                start_time INTEGER NOT NULL,
                end_time INTEGER NOT NULL,
                distance REAL NOT NULL,
                duration INTEGER NOT NULL,
                avg_speed REAL,
                max_speed REAL,
                detected_activity TEXT NOT NULL,
                confidence_score REAL NOT NULL,
                user_confirmed INTEGER DEFAULT 0,
                status TEXT NOT NULL DEFAULT 'completed'
              )
            ''');
            await db.execute('''
              CREATE TABLE route_points (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                trip_id INTEGER NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                altitude REAL,
                timestamp INTEGER NOT NULL,
                accuracy REAL,
                speed REAL,
                FOREIGN KEY (trip_id) REFERENCES trips(id) ON DELETE CASCADE
              )
            ''');
            await db.execute('CREATE INDEX idx_trip_status ON trips(status)');
          },
          onConfigure: service.onConfigure,
        ),
      );
    }

    /// Builds the v3 schema by hand, for the same reason `openV2Database`
    /// exists: the shipped `onCreate` now emits v4. Verbatim copy of the v3
    /// DDL as of `948dff8`.
    Future<Database> openV3Database() async {
      return databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE trips (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                start_time INTEGER NOT NULL,
                end_time INTEGER NOT NULL,
                distance REAL NOT NULL,
                duration INTEGER NOT NULL,
                avg_speed REAL,
                max_speed REAL,
                detected_activity TEXT NOT NULL,
                confidence_score REAL NOT NULL,
                user_confirmed INTEGER DEFAULT 0,
                status TEXT NOT NULL DEFAULT 'completed',
                pause_duration INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await db.execute('''
              CREATE TABLE route_points (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                trip_id INTEGER NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                altitude REAL,
                timestamp INTEGER NOT NULL,
                accuracy REAL,
                speed REAL,
                FOREIGN KEY (trip_id) REFERENCES trips(id) ON DELETE CASCADE
              )
            ''');
            await db.execute('CREATE INDEX idx_trip_status ON trips(status)');
          },
          onConfigure: service.onConfigure,
        ),
      );
    }

    test(
      'v2 -> v3 adds pause_duration and defaults existing rows to 0 (L-073)',
      () async {
        final legacy = await openV2Database();
        addTearDown(legacy.close);

        final legacyId = await legacy.insert('trips', _tripMap());

        final before = await legacy.rawQuery('PRAGMA table_info(trips)');
        expect(
          before.map((c) => c['name']),
          isNot(contains('pause_duration')),
          reason: 'precondition: the v2 schema has no pause_duration column',
        );

        await service.onUpgrade(legacy, 2, AppConstants.databaseVersion);

        final after = await legacy.rawQuery('PRAGMA table_info(trips)');
        final pauseColumn = after.firstWhere(
          (c) => c['name'] == 'pause_duration',
        );
        expect(pauseColumn['notnull'], equals(1));
        expect(pauseColumn['dflt_value'], equals('0'));

        final rows = await legacy.query(
          'trips',
          where: 'id = ?',
          whereArgs: [legacyId],
        );
        expect(rows.first['pause_duration'], equals(0));
        expect(
          Trip.fromMap(rows.first, const []).pauseDuration,
          equals(0),
          reason: 'a migrated row reports no stops, not a wrong number',
        );
        expect(
          rows.first['status'],
          equals(TripStatus.completed.name),
          reason: 'the v2 status column survives the v3 migration untouched',
        );
      },
    );

    test('v3 -> v4 adds suspected_vehicle and leaves existing rows unflagged '
        '(L-106)', () async {
      final legacy = await openV3Database();
      addTearDown(legacy.close);

      final legacyId = await legacy.insert('trips', _tripMap());

      final before = await legacy.rawQuery('PRAGMA table_info(trips)');
      expect(
        before.map((c) => c['name']),
        isNot(contains('suspected_vehicle')),
        reason: 'precondition: the v3 schema has no suspected_vehicle column',
      );

      await service.onUpgrade(legacy, 3, AppConstants.databaseVersion);

      final after = await legacy.rawQuery('PRAGMA table_info(trips)');
      final flagColumn = after.firstWhere(
        (c) => c['name'] == 'suspected_vehicle',
      );
      expect(flagColumn['notnull'], equals(1));
      expect(flagColumn['dflt_value'], equals('0'));

      final rows = await legacy.query(
        'trips',
        where: 'id = ?',
        whereArgs: [legacyId],
      );
      expect(
        Trip.fromMap(rows.first, const []).suspectedVehicle,
        isFalse,
        reason: 'a row written before the flag existed was never judged',
      );
      expect(
        rows.first['pause_duration'],
        equals(0),
        reason: 'the v3 column survives the v4 migration untouched',
      );
    });

    test('v1 -> v4 in one hop applies every step', () async {
      final legacy = await openV1Database();
      addTearDown(legacy.close);

      final legacyId = await legacy.insert('trips', _tripMap());
      await service.onUpgrade(legacy, 1, AppConstants.databaseVersion);

      final rows = await legacy.query(
        'trips',
        where: 'id = ?',
        whereArgs: [legacyId],
      );
      final trip = Trip.fromMap(rows.first, const []);
      expect(trip.status, equals(TripStatus.completed));
      expect(trip.pauseDuration, equals(0));
      expect(trip.suspectedVehicle, isFalse);
    });

    test(
      'round-trips pauseDuration through the shipped schema (L-073)',
      () async {
        final trip = Trip(
          startTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          endTime: DateTime.fromMillisecondsSinceEpoch(1700003600000),
          distance: 12000.0,
          duration: 3000,
          detectedActivity: ActivityType.cycling,
          confidenceScore: 0.9,
          avgSpeed: 14.4,
          maxSpeed: 31.0,
          pauseDuration: 600,
        );

        final id = await db.insert('trips', trip.toMap());
        final rows = await db.query('trips', where: 'id = ?', whereArgs: [id]);

        expect(rows.first['pause_duration'], equals(600));

        final readBack = Trip.fromMap(rows.first, const []);
        expect(readBack.pauseDuration, equals(600));
        expect(readBack.duration, equals(3000));
        expect(readBack.movingDuration, equals(const Duration(seconds: 3000)));
        expect(readBack.pausedDuration, equals(const Duration(seconds: 600)));
        expect(readBack.totalDuration, equals(const Duration(seconds: 3600)));
        expect(readBack.totalDuration, equals(readBack.tripDuration));
      },
    );

    test(
      'round-trips suspectedVehicle through the shipped schema (L-106)',
      () async {
        // SQLite has no bool: the flag is an INTEGER 0/1 like `user_confirmed`.
        final flagged = Trip(
          startTime: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          endTime: DateTime.fromMillisecondsSinceEpoch(1700003600000),
          distance: 64480.0,
          duration: 6576,
          detectedActivity: ActivityType.cycling,
          confidenceScore: 0.9,
          avgSpeed: 35.5,
          maxSpeed: 59.6,
          suspectedVehicle: true,
        );

        final id = await db.insert('trips', flagged.toMap());
        final rows = await db.query('trips', where: 'id = ?', whereArgs: [id]);

        expect(rows.first['suspected_vehicle'], equals(1));
        expect(Trip.fromMap(rows.first, const []).suspectedVehicle, isTrue);

        // And the default is honestly false, not null.
        final plainId = await db.insert(
          'trips',
          flagged.copyWith(suspectedVehicle: false).toMap(),
        );
        final plain = await db.query(
          'trips',
          where: 'id = ?',
          whereArgs: [plainId],
        );
        expect(rows.first['suspected_vehicle'], equals(1));
        expect(Trip.fromMap(plain.first, const []).suspectedVehicle, isFalse);
      },
    );
  });

  group('databaseProvider', () {
    test('exposes the opened database and closes it on dispose', () async {
      final container = ProviderContainer();
      final provided = await container.read(databaseProvider.future);

      expect(provided.isOpen, isTrue);
      expect(identical(provided, db), isTrue);

      container.dispose();
      await pumpEventQueue();

      expect(provided.isOpen, isFalse);

      // Re-open for tearDown's benefit.
      db = await service.database;
    });
  });
}

Map<String, Object?> _tripMap() => {
  'start_time': DateTime.now().millisecondsSinceEpoch,
  'end_time': DateTime.now().millisecondsSinceEpoch,
  'distance': 5000.0,
  'duration': 3600,
  'detected_activity': 'cycling',
  'confidence_score': 0.92,
  'user_confirmed': 0,
};

Future<int> _countTrips(Database db) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM trips');
  return rows.first['c']! as int;
}
