import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:autoride/features/trip_detection/domain/models/trip.dart';
import 'package:autoride/features/trip_detection/domain/models/location_data.dart';
import 'package:autoride/core/theme/app_colors.dart';

/// Map view widget for displaying trip route and current location
///
/// Features:
/// - OpenStreetMap tiles
/// - Route polyline from trip points
/// - Current location marker with animation
/// - Auto-follow mode for tracking current position
class TripMapView extends StatefulWidget {
  const TripMapView({
    required this.controller,
    required this.routePoints,
    required this.followLocation,
    this.currentLocation,
    this.onMapMoved,
    super.key,
  });

  /// Map controller for programmatic map control
  final MapController controller;

  /// List of route points to display as polyline
  final List<RoutePoint> routePoints;

  /// Current location to display as marker (if available)
  final LocationData? currentLocation;

  /// Whether to auto-center map on current location (required to force explicit choice)
  final bool followLocation;

  /// Callback when user manually pans/zooms the map
  final VoidCallback? onMapMoved;

  @override
  State<TripMapView> createState() => _TripMapViewState();
}

class _TripMapViewState extends State<TripMapView> {
  @override
  void didUpdateWidget(TripMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Auto-center map on current location if follow mode is enabled
    if (widget.followLocation &&
        widget.currentLocation != null &&
        widget.currentLocation != oldWidget.currentLocation) {
      _centerOnCurrentLocation();
    }
  }

  void _centerOnCurrentLocation() {
    if (widget.currentLocation == null) return;

    widget.controller.move(
      LatLng(
        widget.currentLocation!.latitude,
        widget.currentLocation!.longitude,
      ),
      widget.controller.camera.zoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Convert route points to LatLng for polyline
    final polylinePoints = widget.routePoints
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();

    // Determine initial center point
    final centerPoint = widget.currentLocation != null
        ? LatLng(
            widget.currentLocation!.latitude,
            widget.currentLocation!.longitude,
          )
        : polylinePoints.isNotEmpty
            ? polylinePoints.last
            : const LatLng(0, 0); // Fallback to 0,0 (unlikely)

    return FlutterMap(
      mapController: widget.controller,
      options: MapOptions(
        initialCenter: centerPoint,
        initialZoom: 15.0,
        minZoom: 10.0,
        maxZoom: 18.0,
        onPositionChanged: (position, hasGesture) {
          // Notify parent when user manually moves map
          if (hasGesture && widget.onMapMoved != null) {
            widget.onMapMoved!();
          }
        },
      ),
      children: [
        // OpenStreetMap tile layer
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'io.github.glandais.autoride',
          maxNativeZoom: 19,
          maxZoom: 19,
          // Handle tile loading errors gracefully
          errorTileCallback: (tile, error, stackTrace) {
            debugPrint('Map tile error: $error');
          },
        ),

        // Route polyline layer
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

        // Current location marker layer
        if (widget.currentLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(
                  widget.currentLocation!.latitude,
                  widget.currentLocation!.longitude,
                ),
                width: 40,
                height: 40,
                alignment: Alignment.center,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.primaryDark
                        : AppColors.primaryLight,
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
                    Icons.navigation,
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
                // Could open OSM copyright page if url_launcher is added
                debugPrint('OpenStreetMap attribution tapped');
              },
            ),
          ],
        ),
      ],
    );
  }
}
