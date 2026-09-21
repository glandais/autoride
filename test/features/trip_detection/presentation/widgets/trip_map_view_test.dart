import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:autoride/features/trip_detection/presentation/widgets/trip_map_view.dart';

import '../../../../helpers/widget/pump_app.dart';

// ===========================================================================
// The OSM tile usage policy requires a visible credit on every map, so the
// attribution is asserted here rather than left to a visual check. Tiles are
// network resources the test binding refuses; flutter_map reports that through
// `errorTileCallback` instead of throwing, so nothing else has to be faked.
// ===========================================================================

void main() {
  testWidgets('shows the OpenStreetMap attribution on the live map', (
    tester,
  ) async {
    final controller = MapController();
    addTearDown(controller.dispose);

    await pumpAppWidget(
      tester,
      SizedBox(
        height: 400,
        child: TripMapView(
          controller: controller,
          routePoints: const [],
          followLocation: false,
        ),
      ),
    );

    expect(find.byType(RichAttributionWidget), findsOneWidget);
    // flutter_map prefixes the source with '©'.
    expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);

    // The credit has to link back to the OSM copyright page; the tap itself
    // hands off to the browser, which a widget test cannot follow.
    // `RichAttributionWidget` adds its own "Made with 'flutter_map'" source, so
    // the OSM one is picked by its text.
    final source = tester.widget<TextSourceAttribution>(
      find.byWidgetPredicate(
        (w) => w is TextSourceAttribution && w.text.contains('OpenStreetMap'),
      ),
    );
    expect(source.onTap, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
