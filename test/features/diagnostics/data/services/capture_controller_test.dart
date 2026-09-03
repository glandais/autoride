import 'dart:async';
import 'dart:convert';

import 'package:autoride/core/audit/audit_event.dart';
import 'package:autoride/core/audit/audit_level.dart';
import 'package:autoride/core/audit/audit_log.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/features/diagnostics/data/services/audit_database.dart';
import 'package:autoride/features/diagnostics/data/services/audit_log_controller.dart';
import 'package:autoride/features/diagnostics/data/services/capture_controller.dart';
import 'package:autoride/features/diagnostics/data/services/sqlite_audit_sink.dart';
import 'package:autoride/features/diagnostics/domain/models/capture_session.dart';
import 'package:autoride/features/settings/data/services/settings_service.dart';
import 'package:autoride/features/settings/domain/models/user_settings.dart';
import 'package:autoride/features/trip_detection/data/services/sensor_service.dart';
import 'package:autoride/features/trip_detection/domain/models/motion_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../helpers/test_database.dart';

/// The T034 producer: what actually ends up in the corpus.
///
/// The batching is the part worth pinning. One row per second is what makes
/// 50 Hz affordable at all (3 600 rows/h against 180 000), and the boundary
/// behaviour is what decides whether a window is a second of data or an
/// arbitrary slice of one.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late StreamController<MotionData> motion;
  late DateTime clock;
  var pushed = 0;

  setUp(() {
    AuditLog.uninstall();
    motion = StreamController<MotionData>.broadcast();
    clock = DateTime(2026, 9, 3, 10);
    pushed = 0;
  });

  tearDown(() {
    AuditLog.uninstall();
    unawaited(motion.close());
  });

  ProviderContainer containerWith({bool consent = true, bool journal = false}) {
    final sink = SqliteAuditSink(database: _InMemoryAuditDatabase());
    addTearDown(sink.close);

    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWithValue(
          UserSettings(
            dataCollectionConsent: consent,
            auditLogEnabled: journal,
          ),
        ),
        auditSinkProvider.overrideWithValue(sink),
        motionDataStreamProvider.overrideWith((ref) => motion.stream),
        captureControllerProvider.overrideWith(_TestCaptureController.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Push one sample and let the listener run.
  ///
  /// Every sample is made distinct through [pushed]. Riverpod does not notify a
  /// listener when the new value equals the previous one, and two `MotionData`
  /// with the same axes and the same timestamp are equal under freezed — a
  /// helper that pushed the identical sample twice would silently deliver it
  /// once and test nothing.
  Future<void> push(ProviderContainer container, {double? ax}) async {
    pushed++;
    final at = clock.add(Duration(microseconds: pushed));
    motion.add(
      MotionData(
        accelerometer: AccelerometerData(
          x: ax ?? pushed.toDouble(),
          y: 9.8,
          z: 0.1,
          timestamp: at,
        ),
        gyroscope: GyroscopeData(x: 0.01, y: 0, z: -0.02, timestamp: at),
        timestamp: at,
      ),
    );
    await pumpEventQueue();
  }

  Future<List<Map<String, Object?>>> lines(ProviderContainer container) async {
    await container.read(auditLogControllerProvider.notifier).flush();
    final db = await container
        .read(auditLogControllerProvider.notifier)
        .databaseForExport();
    final rows = await db!.query('audit_events', orderBy: 'id');
    return rows
        .map(
          (row) => jsonDecode(row['line']! as String) as Map<String, Object?>,
        )
        .toList();
  }

  CaptureController controllerOf(ProviderContainer container) {
    final controller = container.read(
      captureControllerProvider.notifier,
    ) as _TestCaptureController;
    controller.clock = () => clock;
    return controller;
  }

  group('consent gating', () {
    test('capture refuses to start without consent', () async {
      final container = containerWith(consent: false);
      final controller = controllerOf(container);

      await controller.start(CaptureActivity.bike);

      expect(controller.isRecording, isFalse);
      expect(AuditLog.captureEnabled, isFalse);
      expect(
        AuditLog.installed,
        isFalse,
        reason: 'a refused capture must not open a database either',
      );
    });

    test('with consent it starts, and the journal stays off', () async {
      final container = containerWith();
      final controller = controllerOf(container);

      await controller.start(CaptureActivity.car);

      expect(controller.isRecording, isTrue);
      expect(AuditLog.captureEnabled, isTrue);
      expect(
        AuditLog.enabled,
        isFalse,
        reason: 'capture is a separate axis, not a third level',
      );
    });
  });

  group('labels', () {
    test('a session opens and closes with a lbl line', () async {
      final container = containerWith();
      final controller = controllerOf(container);

      await controller.start(CaptureActivity.walk);
      await controller.stop();

      final labels = (await lines(container))
          .where((line) => line['e'] == AuditEvent.label)
          .toList();

      expect(labels, hasLength(2));
      expect(labels.first['a'], 'start');
      expect(labels.first['act'], 'walk');
      expect(labels.last['a'], 'stop');
      expect(labels.last['sess'], labels.first['sess']);
    });

    test('starting twice does not relabel the data already recorded', () async {
      final container = containerWith();
      final controller = controllerOf(container);

      await controller.start(CaptureActivity.bike);
      final session = controller.state;
      await controller.start(CaptureActivity.car);

      expect(controller.state, session);
      expect(controller.state!.activity, CaptureActivity.bike);
    });
  });

  group('the per-second batcher', () {
    test('a window holds every sample of its second as one row', () async {
      final container = containerWith();
      final controller = controllerOf(container);
      await controller.start(CaptureActivity.bike);

      for (var i = 0; i < 50; i++) {
        await push(container, ax: i.toDouble());
      }
      // Cross the boundary: the window is flushed by the sample that follows
      // it, which is what makes the batcher need no timer of its own.
      clock = clock.add(AppConstants.captureBatchDuration);
      await push(container);

      final raw = (await lines(container))
          .where((line) => line['e'] == AuditEvent.rawMotion)
          .toList();

      expect(raw, hasLength(1));
      expect(raw.single['n'], 50);
      expect((raw.single['ax']! as List), hasLength(50));
      expect((raw.single['gz']! as List), hasLength(50));
      expect(raw.single['hz'], AppConstants.captureSamplingRate);
    });

    test('n is what was kept, and is not assumed to be hz', () async {
      final container = containerWith();
      final controller = controllerOf(container);
      await controller.start(CaptureActivity.bike);

      // Three samples in a second: an OS that delivered far below the
      // requested rate. The line has to say so rather than pretend to 50.
      for (var i = 0; i < 3; i++) {
        await push(container);
      }
      clock = clock.add(AppConstants.captureBatchDuration);
      await push(container);

      final raw = (await lines(container))
          .firstWhere((line) => line['e'] == AuditEvent.rawMotion);

      expect(raw['n'], 3);
      expect(raw['hz'], AppConstants.captureSamplingRate);
    });

    test('an over-delivering OS is capped, and n records the cap', () async {
      final container = containerWith();
      final controller = controllerOf(container);
      await controller.start(CaptureActivity.bike);

      for (var i = 0; i < AppConstants.captureMaxSamplesPerLine + 20; i++) {
        await push(container);
      }
      clock = clock.add(AppConstants.captureBatchDuration);
      await push(container);

      final raw = (await lines(container))
          .firstWhere((line) => line['e'] == AuditEvent.rawMotion);

      expect(raw['n'], AppConstants.captureMaxSamplesPerLine);
    });

    test(
      'stopping flushes the partial second instead of dropping it',
      () async {
        final container = containerWith();
        final controller = controllerOf(container);
        await controller.start(CaptureActivity.bike);

        await push(container);
        await push(container);
        await controller.stop();

        final all = await lines(container);
        final raw = all.where((line) => line['e'] == AuditEvent.rawMotion);
        expect(raw, hasLength(1));
        expect(raw.single['n'], 2);

        // And the trailing window is written before the closing label, so the
        // data of a session is always inside its own two `lbl` lines.
        final types = all.map((line) => line['e']).toList();
        expect(
          types.lastIndexOf(AuditEvent.rawMotion),
          lessThan(types.lastIndexOf(AuditEvent.label)),
        );
      },
    );

    test('no sample is recorded once the session has stopped', () async {
      final container = containerWith();
      final controller = controllerOf(container);
      await controller.start(CaptureActivity.bike);
      await controller.stop();

      await push(container);
      clock = clock.add(AppConstants.captureBatchDuration);
      await push(container);

      final raw = (await lines(container))
          .where((line) => line['e'] == AuditEvent.rawMotion);
      expect(raw, isEmpty);
      expect(AuditLog.captureEnabled, isFalse);
    });

    test('windows tile the session rather than drifting with lateness', () async {
      final container = containerWith();
      final controller = controllerOf(container);
      await controller.start(CaptureActivity.bike);

      // Two full windows, each crossed a little late. The second window must
      // still be one `captureBatchDuration` after the first, not one after the
      // late sample that closed it.
      await push(container);
      clock = clock.add(
        AppConstants.captureBatchDuration + const Duration(milliseconds: 300),
      );
      await push(container);
      clock = clock.add(const Duration(milliseconds: 700));
      await push(container);

      final raw = (await lines(container))
          .where((line) => line['e'] == AuditEvent.rawMotion)
          .toList();

      expect(
        raw,
        hasLength(2),
        reason: 'the second boundary was pushed forward by the lateness',
      );
    });
  });

  group('the journal axis is untouched', () {
    test('a capture row never lands at journal level', () async {
      final container = containerWith(journal: true);
      final controller = controllerOf(container);
      await controller.start(CaptureActivity.bike);
      await push(container);
      await controller.stop();

      await container.read(auditLogControllerProvider.notifier).flush();
      final db = await container
          .read(auditLogControllerProvider.notifier)
          .databaseForExport();
      final rows = await db!.query(
        'audit_events',
        where: 'type IN (?, ?)',
        whereArgs: <Object?>[AuditEvent.rawMotion, AuditEvent.label],
      );

      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(row['lvl'], 2);
        expect(row['sess'], isNotNull);
      }
    });

    test('a capture-only file still carries a header', () async {
      final container = containerWith();
      final controller = controllerOf(container);
      await controller.start(CaptureActivity.still);
      await controller.stop();

      final header = (await lines(container))
          .firstWhere((line) => line['e'] == AuditEvent.header);

      // `lvl: off` with `cap: true` is exactly the state a reader must be able
      // to recognise: a file that recorded a corpus and no journal.
      expect(header['lvl'], AuditLogLevel.off.label);
      expect(header['cap'], isTrue);
    });
  });
}

/// [CaptureController] with its clock as a seam, so window boundaries are
/// crossed by moving the clock rather than by waiting real seconds.
class _TestCaptureController extends CaptureController {
  DateTime Function() clock = DateTime.now;

  @override
  DateTime now() => clock();
}

/// [AuditDatabase] backed by an in-memory database built from the production
/// schema (L-014).
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
    await db.delete('capture_sessions');
    return db;
  }

  @override
  Future<void> close() async {}
}
