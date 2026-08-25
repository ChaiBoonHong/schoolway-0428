import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/map/schoolway_map.dart';
import 'package:schoolway/models/models.dart';

class RouteHistoryMapViewer extends StatelessWidget {
  final List<RouteBreadcrumb> breadcrumbs;

  const RouteHistoryMapViewer({super.key, required this.breadcrumbs});

  @override
  Widget build(BuildContext context) {
    if (breadcrumbs.isEmpty) {
      return Container(
        height: 240,
        decoration: BoxDecoration(
          color: SchoolWayTheme.muted,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 48, color: SchoolWayTheme.muted),
            SizedBox(height: 8),
            Text(
              AppLocalizations.of(
                context,
              ).noRouteHistoryCoordinatesRecordedForThis,
              style: TextStyle(
                fontFamily: 'Lexend',
                color: SchoolWayTheme.muted,
              ),
            ),
          ],
        ),
      );
    }

    final points = breadcrumbs
        .map((b) => RouteWaypoint(latitude: b.latitude, longitude: b.longitude))
        .where((p) => p.latitude != 0.0 && p.longitude != 0.0)
        .toList();

    if (points.isEmpty) {
      return Container(
        height: 240,
        decoration: BoxDecoration(
          color: SchoolWayTheme.muted,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          AppLocalizations.of(context).validGpsPathDataNotAvailable,
          style: TextStyle(fontFamily: 'Lexend', color: SchoolWayTheme.muted),
        ),
      );
    }

    final startPoint = points.first;
    final endPoint = points.last;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 300,
        child: SchoolWayMap(
          initialCenter: LatLng(startPoint.latitude, startPoint.longitude),
          initialZoom: 14.5,
          polylines: [
            SchoolWayMapPolyline(
              id: 'history-path',
              points: points,
              strokeWidth: 4.5,
              color: SchoolWayTheme.primary,
            ),
          ],
          markers: [
            SchoolWayMapMarker(
              id: 'history-start',
              latitude: startPoint.latitude,
              longitude: startPoint.longitude,
              width: 36,
              height: 36,
              child: Icon(
                Icons.play_circle_fill,
                color: SchoolWayTheme.success,
                size: 32,
              ),
            ),
            SchoolWayMapMarker(
              id: 'history-end',
              latitude: endPoint.latitude,
              longitude: endPoint.longitude,
              width: 36,
              height: 36,
              child: Icon(
                Icons.flag_circle,
                color: SchoolWayTheme.danger,
                size: 32,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
