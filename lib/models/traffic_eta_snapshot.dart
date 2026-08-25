import 'package:cloud_firestore/cloud_firestore.dart';

import 'planned_route.dart';
import 'route_session.dart';

/// Server-side traffic ETA for one upcoming stop.
class TrafficStopEta {
  /// Position within the ordered trip stops (0-based).
  final int stopIndex;

  /// Index within the saved route's ordered stops.
  final int routeStopIndex;

  /// Humanized stop label ("Stop 1").
  final String label;

  /// Cumulative drive time (minutes) from the bus position to this stop.
  final int etaMinutes;

  const TrafficStopEta({
    required this.stopIndex,
    required this.routeStopIndex,
    required this.label,
    required this.etaMinutes,
  });

  factory TrafficStopEta.fromMap(Map<String, dynamic> map) {
    return TrafficStopEta(
      stopIndex: (map['stopIndex'] as num?)?.toInt() ?? 0,
      routeStopIndex: (map['routeStopIndex'] as num?)?.toInt() ?? 0,
      label: map['label'] as String? ?? 'Stop',
      etaMinutes: (map['etaMinutes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'stopIndex': stopIndex,
    'routeStopIndex': routeStopIndex,
    'label': label,
    'etaMinutes': etaMinutes,
  };
}

/// Lifecycle reason codes returned by the `getTrafficEta` callable.
enum TrafficEtaReason {
  ok,
  inactiveSession,
  noRoute,
  noGoogleGeometry,
  staleGps,
  noGps,
  parentNoLinkedStudents,
  allStopsCompleted,
  unknown,
}

TrafficEtaReason trafficEtaReasonFromString(String? raw) {
  switch (raw) {
    case 'ok':
      return TrafficEtaReason.ok;
    case 'inactive-session':
      return TrafficEtaReason.inactiveSession;
    case 'no-route':
      return TrafficEtaReason.noRoute;
    case 'no-google-geometry':
      return TrafficEtaReason.noGoogleGeometry;
    case 'stale-gps':
      return TrafficEtaReason.staleGps;
    case 'no-gps':
      return TrafficEtaReason.noGps;
    case 'parent-no-linked-students':
      return TrafficEtaReason.parentNoLinkedStudents;
    case 'all-stops-completed':
      return TrafficEtaReason.allStopsCompleted;
    default:
      return TrafficEtaReason.unknown;
  }
}

/// Live traffic-optimal route and per-stop ETAs returned by the
/// `getTrafficEta` Firebase Callable. All fields are computed server-side.
class TrafficEtaSnapshot {
  final String sessionId;
  final String? routeId;
  final String? busId;
  final TrafficEtaReason reason;

  /// True when served from the shared 60-second server cache.
  final bool cached;

  /// True when the snapshot is older than the 5-minute expiry window.
  final bool stale;

  /// GPS timestamp that the route was computed from.
  final DateTime? sourceGpsTime;

  /// Server generation time.
  final DateTime? generatedAt;

  /// Time after which the snapshot should be treated as unavailable.
  final DateTime? expiresAt;

  /// Encoded Google polyline for the live route (bus → remaining stops).
  final String? encodedPolyline;

  final int? distanceMeters;
  final int? durationSeconds;
  final int? completedStopIndex;
  final TripDirection tripDirection;
  final List<TrafficStopEta> stopEtas;

  const TrafficEtaSnapshot({
    required this.sessionId,
    this.routeId,
    this.busId,
    this.reason = TrafficEtaReason.unknown,
    this.cached = false,
    this.stale = false,
    this.sourceGpsTime,
    this.generatedAt,
    this.expiresAt,
    this.encodedPolyline,
    this.distanceMeters,
    this.durationSeconds,
    this.completedStopIndex,
    this.tripDirection = TripDirection.toSchool,
    this.stopEtas = const [],
  });

  bool get isOk => reason == TrafficEtaReason.ok;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get isAvailable => isOk && !isExpired;

  /// Age of this snapshot; used for the localized “updated … ago” label.
  Duration? get age =>
      generatedAt == null ? null : DateTime.now().difference(generatedAt!);

  factory TrafficEtaSnapshot.fromCallable(Map<String, dynamic>? data) {
    if (data == null) {
      return const TrafficEtaSnapshot(
        sessionId: '',
        reason: TrafficEtaReason.unknown,
      );
    }
    final stopEtas = <TrafficStopEta>[];
    final rawEtas = data['stopEtas'];
    if (rawEtas is List) {
      for (final item in rawEtas) {
        if (item is Map<String, dynamic>) {
          stopEtas.add(TrafficStopEta.fromMap(item));
        }
      }
    }
    return TrafficEtaSnapshot(
      sessionId: data['sessionId'] as String? ?? '',
      routeId: data['routeId'] as String?,
      busId: data['busId'] as String?,
      reason: trafficEtaReasonFromString(data['reason'] as String?),
      cached: data['cached'] as bool? ?? false,
      stale: data['stale'] as bool? ?? false,
      sourceGpsTime: _toDate(data['sourceGpsTime']),
      generatedAt: _toDate(data['generatedAt']),
      expiresAt: _toDate(data['expiresAt']),
      encodedPolyline: data['polyline'] as String?,
      distanceMeters: (data['distanceMeters'] as num?)?.toInt(),
      durationSeconds: (data['durationSeconds'] as num?)?.toInt(),
      completedStopIndex: (data['completedStopIndex'] as num?)?.toInt(),
      tripDirection: tripDirectionFromFirestore(data['tripDirection']),
      stopEtas: stopEtas,
    );
  }

  static DateTime? _toDate(Object? raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    final text = raw.toString();
    return DateTime.tryParse(text);
  }

  /// Decoded polyline in trip order as route waypoints.
  List<RouteWaypoint> decodeWaypoints() {
    final encoded = encodedPolyline;
    if (encoded == null || encoded.length < 2) return const [];
    return decodeEncodedPolyline(encoded);
  }
}
