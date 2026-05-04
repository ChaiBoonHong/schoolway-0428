import 'package:cloud_firestore/cloud_firestore.dart';

class RouteWaypoint {
  final double latitude;
  final double longitude;

  const RouteWaypoint({
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toMap() => {
        'latitude': latitude,
        'longitude': longitude,
      };

  factory RouteWaypoint.fromMap(Map<String, dynamic> m) {
    return RouteWaypoint(
      latitude: (m['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (m['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Admin-designed path stored in Firestore `planned_routes`.
class PlannedRoute {
  final String id;
  final String name;
  final List<RouteWaypoint> stops;
  final List<RouteWaypoint> waypoints;
  final DateTime createdAt;
  final DateTime? updatedAt;

  PlannedRoute({
    required this.id,
    required this.name,
    this.stops = const [],
    required this.waypoints,
    required this.createdAt,
    this.updatedAt,
  });

  /// Backward-compatible editable stops:
  /// - new docs use [stops] (raw taps)
  /// - old docs fall back to [waypoints]
  List<RouteWaypoint> get editableStops => stops.isNotEmpty ? stops : waypoints;

  factory PlannedRoute.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    List<RouteWaypoint> parseList(Object? raw) {
      final list = <RouteWaypoint>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) {
            list.add(RouteWaypoint.fromMap(item));
          }
        }
      }
      return list;
    }
    final waypointList = parseList(data['waypoints']);
    final stopList = parseList(data['stops']);
    return PlannedRoute(
      id: doc.id,
      name: data['name'] as String? ?? 'Untitled',
      stops: stopList,
      waypoints: waypointList,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'stops': stops.map((w) => w.toMap()).toList(),
      'waypoints': waypoints.map((w) => w.toMap()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }
}
