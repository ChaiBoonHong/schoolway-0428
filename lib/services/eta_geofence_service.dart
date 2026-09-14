import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import '../models/models.dart';
import '../core/diagnostics/app_logger.dart';

enum GeofenceEventType { approachingStop, atStop, departedStop }

class GeofenceEvent {
  final GeofenceEventType type;
  final AssignedRouteStop assignedStop;

  GeofenceEvent({required this.type, required this.assignedStop});

  RouteWaypoint get stop => assignedStop.waypoint;
  int get stopIndex => assignedStop.routeStopIndex;
  int get tripOrderIndex => assignedStop.tripOrderIndex;
  int get serviceStopNumber => assignedStop.serviceStopNumber;
  String get stopLabel => assignedStop.label;
}

/// Geofence zone calculation and dynamic ETA estimation along route waypoints.
class EtaGeofenceService {
  static const Distance _distance = Distance();
  static final Map<String, List<double>> _speedSamples = {};
  static final Map<String, DateTime> _speedSampleTimes = {};

  // Keep track of visited stops for a session to avoid duplicate events
  static final Map<String, Set<int>> _visitedStops = {};
  static final Map<String, int> _currentStop = {};
  static final Set<String> _outsideRoute = {};

  /// Checks if [currentLocation] is within [radiusMeters] of [stopLocation].
  static bool checkInGeofence({
    required LatLng currentLocation,
    required LatLng stopLocation,
    double radiusMeters = 200.0,
  }) {
    final meters = _distance.as(
      LengthUnit.Meter,
      currentLocation,
      stopLocation,
    );
    return meters <= radiusMeters;
  }

  static double distanceFromRouteMeters({
    required LatLng currentLocation,
    required List<RouteWaypoint> routeWaypoints,
  }) {
    if (routeWaypoints.length < 2) return double.infinity;
    final cumulative = <double>[0];
    for (var index = 1; index < routeWaypoints.length; index++) {
      cumulative.add(cumulative.last + 1);
    }
    final along = _distanceAlongRoute(
      currentLocation,
      routeWaypoints,
      cumulative,
    );
    var best = double.infinity;
    for (var index = 0; index < routeWaypoints.length - 1; index++) {
      final start = cumulative[index];
      final end = cumulative[index + 1];
      if (along < start || along > end) continue;
      final fraction = end == start ? 0.0 : (along - start) / (end - start);
      final a = routeWaypoints[index];
      final b = routeWaypoints[index + 1];
      final projected = LatLng(
        a.latitude + (b.latitude - a.latitude) * fraction,
        a.longitude + (b.longitude - a.longitude) * fraction,
      );
      best = math.min(
        best,
        _distance.as(LengthUnit.Meter, currentLocation, projected),
      );
    }
    return best;
  }

  static Future<bool> processRouteCorridorUpdate({
    required String sessionId,
    required String busId,
    required String driverUid,
    required LatLng currentPos,
    required List<RouteWaypoint> routeWaypoints,
    required double corridorMeters,
  }) async {
    final outside =
        distanceFromRouteMeters(
          currentLocation: currentPos,
          routeWaypoints: routeWaypoints,
        ) >
        corridorMeters;
    if (!outside) {
      _outsideRoute.remove(sessionId);
      return false;
    }
    if (!_outsideRoute.add(sessionId)) return false;
    return true;
  }

  /// Records a GPS speed once per sample timestamp and returns a short rolling
  /// average. Very low readings are ignored because a stopped bus still needs
  /// a useful planning ETA; 30 km/h remains the urban fallback.
  static double smoothedSpeedKmh({
    required String key,
    required double speedKmh,
    required DateTime sampledAt,
  }) {
    if (_speedSampleTimes[key] != sampledAt &&
        speedKmh.isFinite &&
        speedKmh > 5 &&
        speedKmh <= 160) {
      final samples = _speedSamples.putIfAbsent(key, () => <double>[]);
      samples.add(speedKmh);
      if (samples.length > 5) samples.removeAt(0);
      _speedSampleTimes[key] = sampledAt;
    }
    final samples = _speedSamples[key];
    if (samples == null || samples.isEmpty) return 30;
    return samples.reduce((a, b) => a + b) / samples.length;
  }

  /// Calculates ETA by projecting the bus and target stop onto the saved Google
  /// polyline, then measuring the remaining road distance between them.
  static int? calculateRouteEtaMinutes({
    required LatLng currentPos,
    required List<RouteWaypoint> routeWaypoints,
    required RouteWaypoint targetStop,
    required double speedKmh,
  }) {
    if (routeWaypoints.length < 2) return null;

    final cumulative = <double>[0];
    for (var i = 1; i < routeWaypoints.length; i++) {
      cumulative.add(
        cumulative.last +
            _distance.as(
              LengthUnit.Meter,
              LatLng(
                routeWaypoints[i - 1].latitude,
                routeWaypoints[i - 1].longitude,
              ),
              LatLng(routeWaypoints[i].latitude, routeWaypoints[i].longitude),
            ),
      );
    }

    final currentAlong = _distanceAlongRoute(
      currentPos,
      routeWaypoints,
      cumulative,
    );
    final targetAlong = _distanceAlongRoute(
      LatLng(targetStop.latitude, targetStop.longitude),
      routeWaypoints,
      cumulative,
    );
    final remainingMeters = targetAlong - currentAlong;
    if (remainingMeters < -50) return null;

    final effectiveSpeed = speedKmh > 5 ? speedKmh : 30;
    final totalSeconds =
        math.max(0, remainingMeters) / ((effectiveSpeed * 1000) / 3600);
    return math.max(1, (totalSeconds / 60).round());
  }

  static double _distanceAlongRoute(
    LatLng point,
    List<RouteWaypoint> route,
    List<double> cumulative,
  ) {
    var bestDistanceSquared = double.infinity;
    var bestAlong = 0.0;
    final latitudeRadians = point.latitude * math.pi / 180;
    final metersPerDegreeLat = 111320.0;
    final metersPerDegreeLon = metersPerDegreeLat * math.cos(latitudeRadians);

    for (var i = 0; i < route.length - 1; i++) {
      final a = route[i];
      final b = route[i + 1];
      final ax = (a.longitude - point.longitude) * metersPerDegreeLon;
      final ay = (a.latitude - point.latitude) * metersPerDegreeLat;
      final bx = (b.longitude - point.longitude) * metersPerDegreeLon;
      final by = (b.latitude - point.latitude) * metersPerDegreeLat;
      final dx = bx - ax;
      final dy = by - ay;
      final lengthSquared = dx * dx + dy * dy;
      final projection = lengthSquared == 0
          ? 0.0
          : ((-ax * dx - ay * dy) / lengthSquared).clamp(0.0, 1.0);
      final px = ax + projection * dx;
      final py = ay + projection * dy;
      final distanceSquared = px * px + py * py;
      if (distanceSquared < bestDistanceSquared) {
        bestDistanceSquared = distanceSquared;
        bestAlong =
            cumulative[i] + projection * (cumulative[i + 1] - cumulative[i]);
      }
    }
    return bestAlong;
  }

  /// Process location update and return geofence event if applicable. Also logs to Firestore.
  static Future<GeofenceEvent?> processLocationUpdate({
    required String sessionId,
    required String busId,
    required String driverUid,
    required LatLng currentPos,
    required List<AssignedRouteStop> stops,
  }) async {
    if (stops.isEmpty) return null;

    _visitedStops.putIfAbsent(sessionId, () => {});
    final visited = _visitedStops[sessionId]!;
    final currentAt = _currentStop[sessionId];

    for (int i = 0; i < stops.length; i++) {
      final assignedStop = stops[i];
      final stop = assignedStop.waypoint;
      final stopPos = LatLng(stop.latitude, stop.longitude);

      final meters = _distance.as(LengthUnit.Meter, currentPos, stopPos);

      if (meters <= 200.0) {
        // We are AT the stop
        if (currentAt != i) {
          if (!visited.contains(i)) {
            // First time arriving at this stop
            visited.add(i);
            _currentStop[sessionId] = i;
            final event = GeofenceEvent(
              type: GeofenceEventType.atStop,
              assignedStop: assignedStop,
            );
            await _logGeofenceEvent(
              sessionId: sessionId,
              busId: busId,
              driverUid: driverUid,
              event: event,
            );
            return event;
          }
        }
      } else if (meters <= 500.0) {
        // We are APPROACHING the stop
        if (!visited.contains(i) && currentAt != i) {
          // Might not want to spam 'approaching'. We could log it but maybe return it to UI
          // Actually, let's keep it simple and just do 'at_stop' as the main event to avoid noise,
          // but we can return approaching if we want a UI toast.
        }
      } else {
        // Departed
        if (currentAt == i) {
          _currentStop.remove(sessionId);
          final event = GeofenceEvent(
            type: GeofenceEventType.departedStop,
            assignedStop: assignedStop,
          );
          await _logGeofenceEvent(
            sessionId: sessionId,
            busId: busId,
            driverUid: driverUid,
            event: event,
          );
          return event;
        }
      }
    }
    return null;
  }

  static Future<void> _logGeofenceEvent({
    required String sessionId,
    required String busId,
    required String driverUid,
    required GeofenceEvent event,
  }) async {
    try {
      await swFirestore
          .collection('route_sessions')
          .doc(sessionId)
          .collection('geofence_events')
          .add({
            'type': switch (event.type) {
              GeofenceEventType.approachingStop => 'approaching_stop',
              GeofenceEventType.atStop => 'at_stop',
              GeofenceEventType.departedStop => 'departed_stop',
            },
            'stopIndex': event.stopIndex,
            'routeStopIndex': event.stopIndex,
            'tripOrderIndex': event.tripOrderIndex,
            'serviceStopNumber': event.serviceStopNumber,
            'stopLabel': event.stopLabel,
            'busId': busId,
            'driverUid': driverUid,
            'latitude': event.stop.latitude,
            'longitude': event.stop.longitude,
            'timestamp': FieldValue.serverTimestamp(),
          });
    } catch (error, stackTrace) {
      AppLogger.warning(
        'location',
        'Stop arrival could not be synchronized.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Watch geofence events for a session
  static Stream<List<Map<String, dynamic>>> watchGeofenceEvents(
    String sessionId,
  ) {
    return swFirestore
        .collection('route_sessions')
        .doc(sessionId)
        .collection('geofence_events')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => doc.data()).toList());
  }

  static void clearSession(String sessionId) {
    _visitedStops.remove(sessionId);
    _currentStop.remove(sessionId);
    _speedSamples.remove(sessionId);
    _speedSampleTimes.remove(sessionId);
    _outsideRoute.remove(sessionId);
  }
}
