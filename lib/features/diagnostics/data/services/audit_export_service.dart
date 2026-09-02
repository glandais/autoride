import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'package:autoride/core/audit/audit_event.dart';
import 'package:autoride/core/audit/audit_schema.dart';
import 'package:autoride/core/constants/app_constants.dart';
import 'package:autoride/core/utils/logger.dart';
import 'package:autoride/features/diagnostics/data/services/audit_log_controller.dart';

part 'audit_export_service.g.dart';

/// Provides the service that turns the audit log into a shareable file.
@riverpod
AuditExportService auditExportService(Ref ref) =>
    AuditExportService(ref.read(auditLogControllerProvider.notifier));

/// Writes the audit log out as gzipped NDJSON and hands it to the OS share
/// sheet.
///
/// Same shape as [TripExportService], with one deliberate difference: no
/// isolate. A sqflite handle cannot cross an isolate boundary and plugins are
/// unavailable inside `Isolate.run`, so the alternative would be to materialize
/// the whole log as a `String`, ship it across, and compress it there — tens of
/// megabytes of heap for a file that ends up around 3 MB. Streaming through
/// `gzip.encoder` avoids both: it yields between 64 KB chunks, so the work is
/// spread over hundreds of microtasks with a flat memory profile.
class AuditExportService {
  const AuditExportService(this._controller);

  /// The log's lifetime owner, which holds the connection and the buffer.
  ///
  /// Held directly rather than through a `Ref`: this provider is autoDispose,
  /// so a captured `Ref` is already invalid by the time an export runs.
  final AuditLogController _controller;

  static const Logger _logger = Logger('AuditExportService');

  /// Export the log and open the system share sheet.
  ///
  /// [sharePosition] is the source rect iPads need to anchor the popover.
  /// [since] limits the export to events at or after that instant; the whole
  /// log is exported when it is null.
  Future<File> shareLog({Rect? sharePosition, DateTime? since}) async {
    final file = await writeLogFile(since: since);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/gzip')],
        fileNameOverrides: [p.basename(file.path)],
        subject: p.basename(file.path),
        sharePositionOrigin: sharePosition,
      ),
    );

    return file;
  }

  /// Write the log to a gzipped NDJSON file in the cache directory.
  Future<File> writeLogFile({DateTime? since}) async {
    // Without this the last seconds — the ones the user just provoked and is
    // exporting the log to show — would still be sitting in the buffer.
    await _controller.flush();

    final directory = await getTemporaryDirectory();
    final exports = Directory(p.join(directory.path, 'audit_exports'));
    await exports.create(recursive: true);

    final file = File(p.join(exports.path, fileNameFor(DateTime.now())));

    // Reuse the sink's own connection: the log is being written while it is
    // read, and a second handle on the same WAL is a complication with no
    // upside. A null database means the log has never been on.
    final database = await _controller.databaseForExport();
    if (database == null) {
      throw StateError('The audit log has recorded nothing to export');
    }

    await _lines(
      database,
      since,
    ).transform(utf8.encoder).transform(gzip.encoder).pipe(file.openWrite());

    _logger.info(
      'Exported the audit log to ${file.path} (${await file.length()} bytes)',
    );

    return file;
  }

  /// `autoride-audit-YYYYMMDD-HHMM.ndjson.gz`, in local time like the FIT
  /// export — the maintainer reads it next to a ride, not next to a UTC clock.
  static String fileNameFor(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${at.year}${two(at.month)}${two(at.day)}-'
        '${two(at.hour)}${two(at.minute)}';
    return 'autoride-audit-$stamp.ndjson.gz';
  }

  /// The header line followed by every stored line, oldest first.
  Stream<String> _lines(Database db, DateTime? since) async* {
    yield '${await _header(db, since)}\n';

    final from = since?.millisecondsSinceEpoch ?? 0;
    var lastId = 0;

    while (true) {
      // Keyset pagination. `OFFSET` would re-scan everything it skips, which on
      // the last page of a 200 000-row log means scanning the whole table.
      final rows = await db.query(
        'audit_events',
        columns: <String>['id', 'line'],
        where: 't >= ? AND id > ?',
        whereArgs: <Object?>[from, lastId],
        orderBy: 'id',
        limit: AppConstants.auditExportPageSize,
      );
      if (rows.isEmpty) return;

      for (final row in rows) {
        lastId = row['id']! as int;
        yield '${row['line']}\n';
      }
    }
  }

  /// The header, rebuilt at export time.
  ///
  /// Rebuilt rather than read back from the database because it describes the
  /// *file*: its span, its count, and the build and device it came from.
  /// `k` carries this build's thresholds, which is what makes the file
  /// interpretable weeks later — reading today's `AppConstants` to explain a
  /// decision an older build took is how you conclude the opposite of what
  /// happened.
  Future<String> _header(Database db, DateTime? since) async {
    final from = since?.millisecondsSinceEpoch ?? 0;
    final summary = await db.rawQuery(
      'SELECT COUNT(*) AS n, MIN(t) AS lo, MAX(t) AS hi FROM audit_events '
      'WHERE t >= ?',
      <Object?>[from],
    );
    final row = summary.first;

    final package = await PackageInfo.fromPlatform();
    final device = await _deviceDescription();
    final now = DateTime.now();

    return AuditEvent.encode(now.millisecondsSinceEpoch, AuditEvent.header, {
      'sv': AuditSchema.version,
      'app': '${package.version}+${package.buildNumber}',
      'os': device.os,
      'dev': device.model,
      // The offset, not the zone name: it is what converts the file's UTC
      // milliseconds into the times the rider actually experienced.
      'tz': _offsetLabel(now.timeZoneOffset),
      'tzn': now.timeZoneName,
      'n': row['n'],
      'from': row['lo'],
      'to': row['hi'],
      'exp': now.millisecondsSinceEpoch,
      'k': AuditSchema.thresholds(),
    });
  }

  Future<({String os, String model})> _deviceDescription() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        return (
          os: 'Android ${info.version.release} (API ${info.version.sdkInt})',
          model: '${info.manufacturer} ${info.model}',
        );
      }
      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        return (
          os: '${info.systemName} ${info.systemVersion}',
          model: info.utsname.machine,
        );
      }
    } catch (e) {
      // A log without a device name is still worth having.
      _logger.warning('Could not read device info for the audit header: $e');
    }
    return (os: Platform.operatingSystemVersion, model: 'unknown');
  }

  static String _offsetLabel(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final absolute = offset.abs();
    String two(int value) => value.toString().padLeft(2, '0');
    return '$sign${two(absolute.inHours)}:${two(absolute.inMinutes % 60)}';
  }
}
