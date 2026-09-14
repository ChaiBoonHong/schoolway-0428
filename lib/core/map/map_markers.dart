import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:schoolway/core/fleet_bus_colors.dart';
import 'package:schoolway/core/map/schoolway_map.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';

/// Points from the bottom of the bus marker circle down to the exact GPS
/// position so the marker visibly pins the location instead of floating.
class _MarkerTailPainter extends CustomPainter {
  const _MarkerTailPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MarkerTailPainter oldDelegate) =>
      oldDelegate.color != color;
}

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
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: SchoolWayTheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withValues(alpha: 0.55)),
          boxShadow: [BoxShadow(color: SchoolWayTheme.text26, blurRadius: 4)],
        ),
        child: Text(
          busLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: SchoolWayTheme.navy,
            height: 1.1,
          ),
        ),
      ),
      const SizedBox(height: 2),
      Container(
        key: ValueKey('fleet-bus-marker-circle-$busId'),
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
          border: Border.all(color: SchoolWayTheme.surface, width: 2),
          boxShadow: [
            BoxShadow(
              color: SchoolWayTheme.text26,
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: FaIcon(
          FontAwesomeIcons.bus,
          key: ValueKey('fleet-bus-marker-icon-$busId'),
          color: SchoolWayTheme.surface,
          size: 15,
        ),
      ),
      CustomPaint(
        size: const Size(12, 5),
        painter: _MarkerTailPainter(color: accent),
      ),
    ],
  );
}

/// Numbered stop pin widget used by the route planner, driver map, and fleet
/// view. [number] is the 1-based service stop number. Set [badgeLabel] to
/// show an arbitrary caption above the pin (e.g. an ETA); [studentCount]
/// provides the default "N students" caption.
Widget buildStopNumberWidget({
  required int number,
  int? studentCount,
  String? badgeLabel,
  Color color = SchoolWayTheme.accent,
}) {
  final caption =
      badgeLabel ??
      ((studentCount != null && studentCount > 0)
          ? '$studentCount student${studentCount > 1 ? 's' : ''}'
          : null);
  return Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      if (caption != null) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: SchoolWayTheme.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color, width: 1),
          ),
          child: Text(
            caption,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
              color: SchoolWayTheme.navy,
            ),
          ),
        ),
        const SizedBox(height: 2),
      ],
      Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: SchoolWayTheme.surface, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          '$number',
          style: const TextStyle(
            fontFamily: 'Lexend',
            color: SchoolWayTheme.surface,
            fontWeight: FontWeight.w700,
            fontSize: 10,
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
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: SchoolWayTheme.navy,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              blurRadius: 3,
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
            fontSize: 9.5,
            height: 1.1,
            color: SchoolWayTheme.surface,
          ),
        ),
      ),
      // Brand primary, not danger red: an ordinary stop is not an alert.
      const Icon(Icons.location_on, color: SchoolWayTheme.primary, size: 24),
    ],
  );
}

/// Route planner school endpoint pin with visible label badge and school icon.
Widget buildRoutePlannerSchoolPinWidget({required String label}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
        decoration: BoxDecoration(
          color: SchoolWayTheme.navy,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              blurRadius: 3,
              color: SchoolWayTheme.text26,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w800,
            fontSize: 9.5,
            height: 1.1,
            color: SchoolWayTheme.surface,
          ),
        ),
      ),
      const Icon(Icons.school, color: SchoolWayTheme.primary, size: 24),
    ],
  );
}

/// Standard "you are here" marker: a solid info-blue dot inside a
/// translucent halo, centred exactly on the reported position. Shared by the
/// parent, driver, and admin maps so self-location always looks and anchors
/// identically.
SchoolWayMapMarker buildMyLocationMarker({
  required String id,
  required LatLng position,
}) {
  return SchoolWayMapMarker(
    id: id,
    latitude: position.latitude,
    longitude: position.longitude,
    width: 28,
    height: 28,
    alignment: Alignment.center,
    child: Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SchoolWayTheme.info.withValues(alpha: 0.25),
      ),
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: SchoolWayTheme.info,
          border: Border.all(color: SchoolWayTheme.surface, width: 2.5),
        ),
      ),
    ),
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
