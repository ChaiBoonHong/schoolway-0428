import 'package:latlong2/latlong.dart';
import '../models/models.dart';

/// Geofence zone calculation and dynamic ETA estimation along route waypoints.
class EtaGeofenceService {
  static const Distance _distance = Distance();

  /// Checks if [currentLocation] is within [radiusMeters] of [stopLocation].
  static bool checkInGeofence({
    required LatLng currentLocation,
    required LatLng stopLocation,
    double radiusMeters = 200.0,
  }) {
    final meters = _distance.as(LengthUnit.Meter, currentLocation, stopLocation);
    return meters <= radiusMeters;
  }

  /// Calculates dynamic ETA in minutes to a target stop given remaining waypoints and average bus speed.
  /// [speedKmh] defaults to 30 km/h urban bus speed if zero or invalid.
  static int calculateEtaMinutes({
    required LatLng currentPos,
    required List<RouteWaypoint> remainingStops,
    double speedKmh = 30.0,
  }) {
    if (remainingStops.isEmpty) return 0;

    final effectiveSpeedKmh = speedKmh > 5.0 ? speedKmh : 30.0;
    final metersPerSecond = (effectiveSpeedKmh * 1000) / 3600;

    double totalMeters = 0;
    LatLng prev = currentPos;

    for (final stop in remainingStops) {
      final next = LatLng(stop.latitude, stop.longitude);
      totalMeters += _distance.as(LengthUnit.Meter, prev, next);
      prev = next;
    }

    final totalSeconds = totalMeters / metersPerSecond;
    final minutes = (totalSeconds / 60).round();
    return minutes < 1 ? 1 : minutes;
  }

  /// Finds closest stop from current location.
  static RouteWaypoint? findNearestStop({
    required LatLng currentPos,
    required List<RouteWaypoint> stops,
  }) {
    if (stops.isEmpty) return null;
    RouteWaypoint? nearest;
    double minMeters = double.infinity;

    for (final stop in stops) {
      final meters = _distance.as(
        LengthUnit.Meter,
        currentPos,
        LatLng(stop.latitude, stop.longitude),
      );
      if (meters < minMeters) {
        minMeters = meters;
        nearest = stop;
      }
    }

    return nearest;
  }
}
