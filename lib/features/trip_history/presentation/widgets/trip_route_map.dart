import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/core/theme/app_colors.dart';

/// Static map widget displaying a trip route with start/end markers
///
/// Features:
/// - Route polyline
/// - Start marker (green)
/// - End marker (red)
/// - Auto-zoom to fit route bounds
class TripRouteMap extends StatefulWidget {
  const TripRouteMap({
    required this.routePoints,
    this.height = 250,
    super.key,
  });

  final List<RoutePoint> routePoints;
  final double height;

  @override
  State<TripRouteMap> createState() => _TripRouteMapState();
}

class _TripRouteMapState extends State<TripRouteMap> {
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    // Fit bounds after map is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.routePoints.length >= 2) {
        _fitBounds();
      }
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Fit map to show entire route
  void _fitBounds() {
    if (widget.routePoints.isEmpty) return;

    final points = widget.routePoints
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();

    // Calculate bounds
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    // Add padding to bounds
    const padding = 0.001; // ~100m padding
    final bounds = LatLngBounds(
      LatLng(minLat - padding, minLng - padding),
      LatLng(maxLat + padding, maxLng + padding),
    );

    // Fit to bounds
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (widget.routePoints.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Container(
          color: Colors.grey[200],
          child: const Center(
            child: Text('No route data available'),
          ),
        ),
      );
    }

    // Convert route points to LatLng
    final polylinePoints = widget.routePoints
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();

    // Get start and end points
    final startPoint = polylinePoints.first;
    final endPoint = polylinePoints.last;

    // Calculate initial center
    final centerPoint = LatLng(
      (startPoint.latitude + endPoint.latitude) / 2,
      (startPoint.longitude + endPoint.longitude) / 2,
    );

    return SizedBox(
      height: widget.height,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: centerPoint,
          initialZoom: 15.0,
          minZoom: 10.0,
          maxZoom: 18.0,
          // Disable interaction for static display (can be enabled if needed)
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all,
          ),
        ),
        children: [
          // OpenStreetMap tile layer
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'io.github.glandais.autoride',
            maxNativeZoom: 19,
            maxZoom: 19,
            errorTileCallback: (tile, error, stackTrace) {
              debugPrint('Map tile error: $error');
            },
          ),

          // Route polyline
          if (polylinePoints.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: polylinePoints,
                  strokeWidth: 4.0,
                  color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                  borderStrokeWidth: 2.0,
                  borderColor: theme.colorScheme.surface.withValues(alpha: 0.8),
                ),
              ],
            ),

          // Start and end markers
          MarkerLayer(
            markers: [
              // Start marker (green)
              Marker(
                point: startPoint,
                width: 40,
                height: 40,
                alignment: Alignment.center,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.surface,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),

              // End marker (red)
              Marker(
                point: endPoint,
                width: 40,
                height: 40,
                alignment: Alignment.center,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.surface,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.stop,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),

          // OSM attribution (required)
          RichAttributionWidget(
            alignment: AttributionAlignment.bottomLeft,
            attributions: [
              TextSourceAttribution(
                'OpenStreetMap contributors',
                onTap: () {
                  debugPrint('OpenStreetMap attribution tapped');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
