import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:autoride/features/trip_detection/data/services/database_service.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/activity_confidence.dart';

void main() {
  // Initialize FFI for desktop testing
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late DatabaseService dbService;

  setUp(() async {
    dbService = DatabaseService();
    // Use in-memory database for tests
    await dbService.deleteDatabase();
  });

  tearDown(() async {
    await dbService.close();
    await dbService.deleteDatabase();
  });

  group('DatabaseService', () {
    test('should initialize database successfully', () async {
      final db = await dbService.database;

      expect(db, isNotNull);
      expect(db.isOpen, isTrue);
    });

    test('should create trips table', () async {
      final db = await dbService.database;

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='trips'",
      );

      expect(tables, isNotEmpty);
      expect(tables.first['name'], equals('trips'));
    });

    test('should create route_points table', () async {
      final db = await dbService.database;

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='route_points'",
      );

      expect(tables, isNotEmpty);
      expect(tables.first['name'], equals('route_points'));
    });

    test('should create indexes', () async {
      final db = await dbService.database;

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      );

      final indexNames = indexes.map((e) => e['name'] as String).toList();

      expect(indexNames, contains('idx_trip_start_time'));
      expect(indexNames, contains('idx_trip_end_time'));
      expect(indexNames, contains('idx_route_points_trip_id'));
      expect(indexNames, contains('idx_route_points_timestamp'));
    });

    test('should enable foreign keys', () async {
      final db = await dbService.database;

      final result = await db.rawQuery('PRAGMA foreign_keys');

      expect(result.first['foreign_keys'], equals(1));
    });

    test('should insert and retrieve trip', () async {
      final db = await dbService.database;

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

      // Insert trip
      final tripId = await db.insert('trips', trip.toMap());

      expect(tripId, greaterThan(0));

      // Retrieve trip
      final result = await db.query(
        'trips',
        where: 'id = ?',
        whereArgs: [tripId],
      );

      expect(result, hasLength(1));
      expect(result.first['distance'], equals(5000.0));
      expect(result.first['detected_activity'], equals('cycling'));
    });

    test('should insert and retrieve route points', () async {
      final db = await dbService.database;

      // First insert a trip
      final tripMap = {
        'start_time': DateTime.now().millisecondsSinceEpoch,
        'end_time': DateTime.now().millisecondsSinceEpoch,
        'distance': 5000.0,
        'duration': 3600,
        'detected_activity': 'cycling',
        'confidence_score': 0.92,
        'user_confirmed': 0,
      };

      final tripId = await db.insert('trips', tripMap);

      // Insert route points
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

      // Retrieve route points
      final result = await db.query(
        'route_points',
        where: 'trip_id = ?',
        whereArgs: [tripId],
      );

      expect(result, hasLength(1));
      expect(result.first['latitude'], equals(48.8566));
      expect(result.first['longitude'], equals(2.3522));
    });

    test('should cascade delete route points when trip is deleted', () async {
      final db = await dbService.database;

      // Insert trip
      final tripMap = {
        'start_time': DateTime.now().millisecondsSinceEpoch,
        'end_time': DateTime.now().millisecondsSinceEpoch,
        'distance': 5000.0,
        'duration': 3600,
        'detected_activity': 'cycling',
        'confidence_score': 0.92,
        'user_confirmed': 0,
      };

      final tripId = await db.insert('trips', tripMap);

      // Insert route points
      final point = RoutePoint(
        tripId: tripId,
        latitude: 48.8566,
        longitude: 2.3522,
        timestamp: DateTime.now(),
      );

      await db.insert('route_points', point.toMap());

      // Verify route point exists
      var routePoints = await db.query(
        'route_points',
        where: 'trip_id = ?',
        whereArgs: [tripId],
      );
      expect(routePoints, hasLength(1));

      // Delete trip
      await db.delete('trips', where: 'id = ?', whereArgs: [tripId]);

      // Verify route points are also deleted (CASCADE)
      routePoints = await db.query(
        'route_points',
        where: 'trip_id = ?',
        whereArgs: [tripId],
      );
      expect(routePoints, isEmpty);
    });
  });
}
