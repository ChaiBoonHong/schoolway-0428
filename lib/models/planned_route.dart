import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

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

bool routeWaypointIsNear(
  RouteWaypoint point,
  RouteWaypoint target, {
  double toleranceMeters = 10,
}) {
  const distance = Distance();
  return distance.as(
        LengthUnit.Meter,
        LatLng(point.latitude, point.longitude),
        LatLng(target.latitude, target.longitude),
      ) <=
      toleranceMeters;
}

/// Returns a route whose final point is the configured school endpoint.
/// Existing points keep their indices; a nearby endpoint is normalized to the
/// exact configured coordinate and a missing endpoint is appended.
List<RouteWaypoint> ensureSchoolRouteEndpoint(
  Iterable<RouteWaypoint> stops,
  RouteWaypoint school,
) {
  final result = List<RouteWaypoint>.from(stops);
  if (result.isEmpty) return [school];
  if (routeWaypointIsNear(result.last, school)) {
    result[result.length - 1] = school;
  } else {
    result.add(school);
  }
  return result;
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
      if (index >= encoded.length) break;
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    latitude += result & 1 != 0 ? ~(result >> 1) : (result >> 1);

    result = 0;
    shift = 0;
    do {
      if (index >= encoded.length) break;
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

/// Encodes ordered [RouteWaypoint]s into a Google encoded polyline.
String encodeEncodedPolyline(List<RouteWaypoint> points) {
  String encodeValue(int value) {
    var number = value < 0 ? ~(value << 1) : value << 1;
    final buffer = StringBuffer();
    while (number >= 0x20) {
      buffer.writeCharCode((0x20 | (number & 0x1f)) + 63);
      number >>= 5;
    }
    buffer.writeCharCode(number + 63);
    return buffer.toString();
  }

  var prevLat = 0;
  var prevLng = 0;
  final buffer = StringBuffer();
  for (final point in points) {
    final lat5 = (point.latitude * 1e5).round();
    final lng5 = (point.longitude * 1e5).round();
    buffer.write(encodeValue(lat5 - prevLat));
    buffer.write(encodeValue(lng5 - prevLng));
    prevLat = lat5;
    prevLng = lng5;
  }
  return buffer.toString();
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

/// Two ordered stop plans produced by splitting one saved route.
class RouteSplitPlan {
  final List<RouteWaypoint> first;

  final List<RouteWaypoint> second;

  /// 1-based stop after which the original plan was split.
  final int splitAfterStop;

  /// Whether the junction stop ends [first] and starts [second].
  final bool shareJunctionStop;

  const RouteSplitPlan({
    required this.first,
    required this.second,
    required this.splitAfterStop,
    required this.shareJunctionStop,
  });

  /// Location of an original 0-based stop index after the split:
  /// part 0 = [first], part 1 = [second]; value is the index inside that
  /// part. The junction stop is owned by part 0. Returns null when
  /// [originalIndex] is out of range.
  (int, int)? positionOfOriginal(int originalIndex) {
    final total = first.length + second.length - (shareJunctionStop ? 1 : 0);
    if (originalIndex < 0 || originalIndex >= total) return null;
    if (originalIndex < splitAfterStop) return (0, originalIndex);
    return (
      1,
      shareJunctionStop
          ? originalIndex - splitAfterStop + 1
          : originalIndex - splitAfterStop,
    );
  }
}

/// Maximum stops Google Compute Routes accepts for one planned route
/// (25 intermediate waypoints + destination; live trips prepend the bus).
const int maxPlannedRouteStops = 26;

/// Splits an ordered stop plan into two drivable parts after 1-based
/// [splitAfterStop]. When [shareJunctionStop] is true the boundary stop ends
/// part one and starts part two, keeping the parts connected for buses.
///
/// Returns null when either part would hold fewer than two or more than
/// [maxPlannedRouteStops] stops.
RouteSplitPlan? planRouteSplit(
  List<RouteWaypoint> stops,
  int splitAfterStop, {
  bool shareJunctionStop = true,
}) {
  if (splitAfterStop < 1 || splitAfterStop >= stops.length) return null;
  var first = stops.sublist(0, splitAfterStop);
  var second = shareJunctionStop
      ? stops.sublist(splitAfterStop - 1)
      : stops.sublist(splitAfterStop);
  if (first.length < 2 ||
      second.length < 2 ||
      first.length > maxPlannedRouteStops ||
      second.length > maxPlannedRouteStops) {
    return null;
  }
  return RouteSplitPlan(
    first: first,
    second: second,
    splitAfterStop: splitAfterStop,
    shareJunctionStop: shareJunctionStop,
  );
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

  /// Route polyline in trip order. Google geometry is the only source.
  List<RouteWaypoint> waypointsForTrip(TripDirection direction) {
    return googleWaypointsForTrip(direction);
  }
}
