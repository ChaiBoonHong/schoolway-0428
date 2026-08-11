import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/models/models.dart';

class RouteHistoryMapViewer extends StatelessWidget {
  final List<RouteBreadcrumb> breadcrumbs;

  const RouteHistoryMapViewer({
    super.key,
    required this.breadcrumbs,
  });

  @override
  Widget build(BuildContext context) {
    if (breadcrumbs.isEmpty) {
      return Container(
        height: 240,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text(
              'No route history coordinates recorded for this trip.',
              style: TextStyle(fontFamily: 'Lexend', color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final points = breadcrumbs
        .map((b) => LatLng(b.latitude, b.longitude))
        .where((p) => p.latitude != 0.0 && p.longitude != 0.0)
        .toList();

    if (points.isEmpty) {
      return Container(
        height: 240,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Valid GPS path data not available.',
          style: TextStyle(fontFamily: 'Lexend', color: Colors.grey),
        ),
      );
    }

    final startPoint = points.first;
    final endPoint = points.last;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 300,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: startPoint,
            initialZoom: 14.5,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.schoolway.app',
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: points,
                  strokeWidth: 4.5,
                  color: const Color(0xFF0077B6),
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: startPoint,
                  width: 36,
                  height: 36,
                  child: const Icon(
                    Icons.play_circle_fill,
                    color: Colors.green,
                    size: 32,
                  ),
                ),
                Marker(
                  point: endPoint,
                  width: 36,
                  height: 36,
                  child: const Icon(
                    Icons.flag_circle,
                    color: Colors.red,
                    size: 32,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
