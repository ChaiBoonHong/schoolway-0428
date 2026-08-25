import 'package:cloud_firestore/cloud_firestore.dart';

import 'route_session.dart';

class RouteWaypoint {
  final double latitude;
  final double longitude;

  const RouteWaypoint({required this.latitude, required this.longitude});

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

/// Decodes a Google encoded polyline into ordered [RouteWaypoint]s.
List<RouteWaypoint> decodeEncodedPolyline(String encoded) {
  final points = <RouteWaypoint>[];
  var index = 0;
  var latitude = 0;
  var longitude = 0;
  while (index < encoded.length) {
    var result = 0;
    var shift = 0;
    int byte;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    latitude += result & 1 != 0 ? ~(result >> 1) : (result >> 1);

    result = 0;
    shift = 0;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    longitude += result & 1 != 0 ? ~(result >> 1) : (result >> 1);

    points.add(
      RouteWaypoint(latitude: latitude * 1e-5, longitude: longitude * 1e-5),
    );
  }
  return points;
}

/// Versioned Google geometry cached on a [PlannedRoute] by the backend
/// `computePlannedRoute` callable. The ordered admin [PlannedRoute.stops]
/// remain the permanent source of truth; this object is display geometry only.
class GoogleRouteGeometry {
  static const String providerName = 'google';

  final String encodedPolyline;
  final int? distanceMeters;
  final int? durationSeconds;
  final int? durationStaticSeconds;

  /// SHA-256 of the ordered stops the geometry was generated from.
  final String stopHash;

  final DateTime generatedAt;
  final DateTime expiresAt;

  /// Per-leg metadata (same length as stops - 1).
  final List<GoogleRouteLeg> legs;

  const GoogleRouteGeometry({
    required this.encodedPolyline,
    this.distanceMeters,
    this.durationSeconds,
    this.durationStaticSeconds,
    required this.stopHash,
    required this.generatedAt,
    required this.expiresAt,
    this.legs = const [],
  });

  bool get isExpired => expiresAt.isBefore(DateTime.now());

  List<RouteWaypoint> decodeWaypoints() =>
      decodeEncodedPolyline(encodedPolyline);

  factory GoogleRouteGeometry.fromMap(Map<String, dynamic> map) {
    final legs = <GoogleRouteLeg>[];
    final rawLegs = map['legs'];
    if (rawLegs is List) {
      for (final item in rawLegs) {
        if (item is Map<String, dynamic>) {
          legs.add(GoogleRouteLeg.fromMap(item));
        }
      }
    }
    return GoogleRouteGeometry(
      encodedPolyline: map['encodedPolyline'] as String? ?? '',
      distanceMeters: (map['distanceMeters'] as num?)?.toInt(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
      durationStaticSeconds: (map['durationStaticSeconds'] as num?)?.toInt(),
      stopHash: map['stopHash'] as String? ?? '',
      generatedAt: _toDate(map['generatedAt']) ?? DateTime.now(),
      expiresAt: _toDate(map['expiresAt']) ?? DateTime.now(),
      legs: legs,
    );
  }

  Map<String, dynamic> toMap() => {
    'provider': providerName,
    'version': 1,
    'encodedPolyline': encodedPolyline,
    'distanceMeters': distanceMeters,
    'durationSeconds': durationSeconds,
    'durationStaticSeconds': durationStaticSeconds,
    'stopHash': stopHash,
    'generatedAt': Timestamp.fromDate(generatedAt),
    'expiresAt': Timestamp.fromDate(expiresAt),
    'legs': legs.map((leg) => leg.toMap()).toList(),
  };

  static DateTime? _toDate(Object? raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString());
  }
}

class GoogleRouteLeg {
  final int? distanceMeters;
  final int? durationSeconds;
  final int? durationStaticSeconds;
  final String? encodedPolyline;

  const GoogleRouteLeg({
    this.distanceMeters,
    this.durationSeconds,
    this.durationStaticSeconds,
    this.encodedPolyline,
  });

  factory GoogleRouteLeg.fromMap(Map<String, dynamic> map) {
    return GoogleRouteLeg(
      distanceMeters: (map['distanceMeters'] as num?)?.toInt(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
      durationStaticSeconds: (map['durationStaticSeconds'] as num?)?.toInt(),
      encodedPolyline: map['encodedPolyline'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'distanceMeters': distanceMeters,
    'durationSeconds': durationSeconds,
    'durationStaticSeconds': durationStaticSeconds,
    'encodedPolyline': encodedPolyline,
  };
}

/// Admin-designed path stored in Firestore `planned_routes`.
class PlannedRoute {
  final String id;
  final String name;
  final List<RouteWaypoint> stops;
  final List<RouteWaypoint> waypoints;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int expectedDurationMinutes;
  final GoogleRouteGeometry? googleGeometry;

  PlannedRoute({
    required this.id,
    required this.name,
    this.stops = const [],
    required this.waypoints,
    required this.createdAt,
    this.updatedAt,
    this.expectedDurationMinutes = 45,
    this.googleGeometry,
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
    final rawGeometry = data['googleGeometry'];
    return PlannedRoute(
      id: doc.id,
      name: data['name'] as String? ?? 'Untitled',
      stops: stopList,
      waypoints: waypointList,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      expectedDurationMinutes: data['expectedDurationMinutes'] as int? ?? 45,
      googleGeometry: rawGeometry is Map<String, dynamic>
          ? GoogleRouteGeometry.fromMap(rawGeometry)
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'stops': stops.map((w) => w.toMap()).toList(),
      'waypoints': waypoints.map((w) => w.toMap()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'expectedDurationMinutes': expectedDurationMinutes,
      if (googleGeometry != null) 'googleGeometry': googleGeometry!.toMap(),
    };
  }

  /// Pin / leg order for the driver map (1 = first stop in this trip).
  List<RouteWaypoint> editableStopsForTrip(TripDirection direction) {
    final s = editableStops;
    return direction == TripDirection.fromSchool
        ? s.reversed.toList()
        : List<RouteWaypoint>.from(s);
  }

  /// Google geometry polyline in trip order (reversed when [fromSchool]).
  List<RouteWaypoint> googleWaypointsForTrip(TripDirection direction) {
    final geometry = googleGeometry;
    if (geometry == null || geometry.encodedPolyline.isEmpty) {
      return const [];
    }
    final decoded = geometry.decodeWaypoints();
    return direction == TripDirection.fromSchool
        ? decoded.reversed.toList()
        : decoded;
  }

  /// Legacy OSRM `waypoints` in trip order. Used on the flutter_map fallback
  /// path so Google route content is never drawn over a non-Google map.
  List<RouteWaypoint> legacyWaypointsForTrip(TripDirection direction) {
    final w = waypoints;
    return direction == TripDirection.fromSchool
        ? w.reversed.toList()
        : List<RouteWaypoint>.from(w);
  }

  /// True when a valid (unexpired) Google geometry exists for this route.
  bool get hasValidGoogleGeometry =>
      googleGeometry != null && !googleGeometry!.isExpired;

  /// Polyline geometry in trip order (reversed OSRM path when [fromSchool]).
  List<RouteWaypoint> waypointsForTrip(TripDirection direction) {
    final google = googleWaypointsForTrip(direction);
    if (google.isNotEmpty) return google;
    final w = waypoints;
    return direction == TripDirection.fromSchool
        ? w.reversed.toList()
        : List<RouteWaypoint>.from(w);
  }
}
