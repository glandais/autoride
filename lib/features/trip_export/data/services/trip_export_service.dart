import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';

import 'package:autoride/core/utils/logger.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_export/data/services/fit_activity_encoder.dart';

part 'trip_export_service.g.dart';

/// Provides the service that turns a trip into a shareable `.fit` file.
@riverpod
TripExportService tripExportService(Ref ref) => const TripExportService();

/// Writes a [Trip] out as a Garmin FIT activity and hands it to the OS share
/// sheet, which is what lets the user drop it into Strava, Garmin Connect,
/// Files, or anything else that accepts a `.fit`.
///
/// The encoding itself lives in [FitActivityEncoder]; this is the thin
/// platform-facing half — temp file, share sheet, cleanup.
class TripExportService {
  const TripExportService();

  static const Logger _logger = Logger('TripExportService');

  /// Encode [trip] and open the system share sheet for the resulting file.
  ///
  /// [sharePosition] is the source rect iPads need to anchor the popover; on
  /// every other platform it is ignored.
  ///
  /// Returns the file that was written. It lives in the cache directory, so the
  /// OS is free to reclaim it once the share completes.
  Future<File> shareAsFit(Trip trip, {Rect? sharePosition}) async {
    final file = await writeFitFile(trip);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/vnd.ant.fit')],
        fileNameOverrides: [p.basename(file.path)],
        subject: FitActivityEncoder.fileNameFor(trip),
        sharePositionOrigin: sharePosition,
      ),
    );

    return file;
  }

  /// Encode [trip] and write it to a `.fit` file in the cache directory.
  ///
  /// Encoding runs on another isolate: a long ride is tens of thousands of
  /// records, and building those on the UI isolate drops frames.
  Future<File> writeFitFile(Trip trip) async {
    final bytes = await Isolate.run(() => FitActivityEncoder.encode(trip));

    final directory = await getTemporaryDirectory();
    final exports = Directory(p.join(directory.path, 'fit_exports'));
    await exports.create(recursive: true);

    final file = File(
      p.join(exports.path, FitActivityEncoder.fileNameFor(trip)),
    );
    await file.writeAsBytes(bytes, flush: true);

    _logger.info(
      'Exported trip ${trip.id} to ${file.path} (${bytes.length} bytes, '
      '${trip.routePoints.length} points)',
    );

    return file;
  }
}
