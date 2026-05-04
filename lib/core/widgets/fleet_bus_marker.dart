import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/fleet_bus_colors.dart';

/// Builds a consistent bus [Marker] used by admin, driver, and parent maps so
/// the same bus always appears at the exact same screen position regardless of
/// which dashboard is viewing it.
Marker buildFleetBusMarker({
  required LatLng point,
  required String busId,
  required String busLabel,
}) {
  final accent = fleetBusAccentColor(busId);
  return Marker(
    point: point,
    width: 90,
    height: 72,
    alignment: Alignment.bottomCenter,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 6,
              ),
            ],
          ),
          child: Text(
            busLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Color(0xFF03045E),
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Icon(Icons.directions_bus, color: accent, size: 34),
      ],
    ),
  );
}
