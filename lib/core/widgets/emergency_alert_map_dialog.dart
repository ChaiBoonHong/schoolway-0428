import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/map/map_markers.dart';
import 'package:schoolway/core/map/schoolway_map.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
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
            SchoolWayMap(
              initialCenter: point,
              initialZoom: 16,
              markers: [
                SchoolWayMapMarker(
                  id: 'emergency-location',
                  latitude: location.latitude,
                  longitude: location.longitude,
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  child: buildEmergencyAlertWidget(),
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
                  backgroundColor: SchoolWayTheme.surface,
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
