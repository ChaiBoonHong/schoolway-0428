import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  String get stopLabel => assignedStop.label;
}

/// Geofence zone calculation and dynamic ETA estimation along route waypoints.
class EtaGeofenceService {
  static const Distance _distance = Distance();

  // Keep track of visited stops for a session to avoid duplicate events
  static final Map<String, Set<int>> _visitedStops = {};
  static final Map<String, int> _currentStop = {};

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

  /// Finds the index of the next unvisited stop for the bus.
  /// Prevents "backward routing" ETA inflation by checking if the bus is already moving towards the stop after the nearest one.
  static int getNextStopIndex({
    required LatLng currentPos,
    required List<RouteWaypoint> stops,
  }) {
    if (stops.isEmpty) return 0;

    int nearestIdx = 0;
    double minDist = double.infinity;

    for (int i = 0; i < stops.length; i++) {
      final meters = _distance.as(
        LengthUnit.Meter,
        currentPos,
        LatLng(stops[i].latitude, stops[i].longitude),
      );
      if (meters < minDist) {
        minDist = meters;
        nearestIdx = i;
      }
    }

    int nextIdx = nearestIdx;
    if (nearestIdx < stops.length - 1) {
      final nearestPos = LatLng(
        stops[nearestIdx].latitude,
        stops[nearestIdx].longitude,
      );
      final nextPos = LatLng(
        stops[nearestIdx + 1].latitude,
        stops[nearestIdx + 1].longitude,
      );

      final distBusToNext = _distance.as(LengthUnit.Meter, currentPos, nextPos);
      final distNearestToNext = _distance.as(
        LengthUnit.Meter,
        nearestPos,
        nextPos,
      );

      // If the distance from the bus to the next stop is less than the distance from the nearest stop to the next stop,
      // it means the bus has already passed the nearest stop and is on the segment heading to the next stop.
      if (distBusToNext < distNearestToNext) {
        nextIdx = nearestIdx + 1;
      }
    }

    return nextIdx;
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
  }
}
