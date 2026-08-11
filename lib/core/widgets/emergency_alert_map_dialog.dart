import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/widgets/osm_map_tile_layer.dart';
import 'package:schoolway/models/emergency_alert.dart';

void showEmergencyAlertMapDialog(BuildContext context, AlertLocation location) {
  final point = LatLng(location.latitude, location.longitude);
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(initialCenter: point, initialZoom: 16),
              children: [
                const OsmMapTileLayer(),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 48,
                      height: 48,
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: SchoolWayTheme.danger,
                        size: 44,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: SchoolWayTheme.spacing8,
              right: SchoolWayTheme.spacing8,
              child: IconButton.filled(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: SchoolWayTheme.text,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
