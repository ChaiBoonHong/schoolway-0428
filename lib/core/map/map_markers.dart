import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:schoolway/core/fleet_bus_colors.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';

/// Bus marker widget; used by all role dashboards so the same bus always
/// appears at the exact same screen position.
Widget buildFleetBusMarkerWidget({
  required String busId,
  required String busLabel,
}) {
  final accent = fleetBusAccentColor(busId);
  return Column(
    key: ValueKey('fleet-bus-$busId'),
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
      Container(
        key: ValueKey('fleet-bus-marker-circle-$busId'),
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 7,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: FaIcon(
          FontAwesomeIcons.bus,
          key: ValueKey('fleet-bus-marker-icon-$busId'),
          color: Colors.white,
          size: 20,
        ),
      ),
    ],
  );
}

/// Numbered stop pin widget used by the route planner, driver map, and fleet
/// view. [number] is the 1-based service stop number.
Widget buildStopNumberWidget({
  required int number,
  int? studentCount,
  Color color = SchoolWayTheme.accent,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      if (studentCount != null && studentCount > 0)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: SchoolWayTheme.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color, width: 1),
          ),
          child: Text(
            '$studentCount student${studentCount > 1 ? 's' : ''}',
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: SchoolWayTheme.navy,
            ),
          ),
        ),
      if (studentCount != null && studentCount > 0) const SizedBox(height: 2),
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: SchoolWayTheme.surface, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          '$number',
          style: const TextStyle(
            fontFamily: 'Lexend',
            color: SchoolWayTheme.surface,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    ],
  );
}

/// Route planner numbered pin (no student count, dark background).
Widget buildRoutePlannerPinWidget(int number) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: SchoolWayTheme.navy,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              blurRadius: 4,
              color: SchoolWayTheme.text26,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          '$number',
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w800,
            fontSize: 11,
            height: 1.1,
            color: SchoolWayTheme.surface,
          ),
        ),
      ),
      const Icon(Icons.location_on, color: SchoolWayTheme.danger, size: 32),
    ],
  );
}

/// Emergency alert icon widget.
Widget buildEmergencyAlertWidget() {
  return const Icon(
    Icons.warning_amber_rounded,
    color: SchoolWayTheme.danger,
    size: 44,
  );
}
