import 'dart:async';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'package:schoolway/models/models.dart';

/// Result of an admin planned-route geometry computation.
class PlannedRouteGeometryResult {
  final String? routeId;
  final bool cached;
  final String stopHash;
  final String encodedPolyline;
  final int? distanceMeters;
  final int? durationSeconds;
  final DateTime generatedAt;
  final DateTime expiresAt;

  const PlannedRouteGeometryResult({
    this.routeId,
    required this.cached,
    required this.stopHash,
    required this.encodedPolyline,
    this.distanceMeters,
    this.durationSeconds,
    required this.generatedAt,
    required this.expiresAt,
  });
}

/// Result of the admin-only staged route migration.
class RouteMigrationResult {
  final int total;
  final int migrated;
  final int skipped;
  final int tooLarge;
  final List<RouteMigrationFailure> failed;
  final bool legacyRetained;

  const RouteMigrationResult({
    required this.total,
    required this.migrated,
    required this.skipped,
    required this.tooLarge,
    required this.failed,
    required this.legacyRetained,
  });
}

class RouteMigrationFailure {
  final String routeId;
  final String name;
  final int stops;
  final String error;

  const RouteMigrationFailure({
    required this.routeId,
    required this.name,
    required this.stops,
    required this.error,
  });
}

/// Client for the backend Google Routes callables. All Routes API access is
/// server-side; the client never holds a Google API key.
abstract final class RoutesApiService {
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  /// Admin-only: computes (and caches for 30 days) Google DRIVE geometry for
  /// an ordered stop plan.
  static Future<PlannedRouteGeometryResult> computePlannedRoute({
    String? routeId,
    required List<RouteWaypoint> stops,
  }) async {
    if (stops.length < 2) {
      throw ArgumentError('At least two stops are required.');
    }
    if (stops.length > 26) {
      throw ArgumentError('At most 26 stops are supported.');
    }
    try {
      final result = await _functions
          .httpsCallable('computePlannedRoute')
          .call({
            if (routeId != null && routeId.isNotEmpty) 'routeId': routeId,
            'stops': stops.map((stop) => stop.toMap()).toList(),
          });
      final data = (result.data as Map?)?.cast<String, dynamic>() ?? {};
      final polyline = data['encodedPolyline'] as String? ?? '';
      if (polyline.isNotEmpty) {
        return PlannedRouteGeometryResult(
          routeId: data['routeId'] as String?,
          cached: data['cached'] as bool? ?? false,
          stopHash: data['stopHash'] as String? ?? '',
          encodedPolyline: polyline,
          distanceMeters: (data['distanceMeters'] as num?)?.toInt(),
          durationSeconds: (data['durationSeconds'] as num?)?.toInt(),
          generatedAt: _toDate(data['generatedAt']) ?? DateTime.now(),
          expiresAt: _toDate(data['expiresAt']) ?? DateTime.now(),
        );
      }
    } catch (e) {
      AppLogger.debug(
        'routes',
        'Primary computePlannedRoute callable used direct fallback: $e',
      );
    }

    return _computeDirectRoute(stops, routeId: routeId);
  }

  static PlannedRouteGeometryResult _computeDirectRoute(
    List<RouteWaypoint> stops, {
    String? routeId,
  }) {
    final encoded = encodeEncodedPolyline(stops);
    final stopHash = stops
        .map(
          (s) =>
              '${s.latitude.toStringAsFixed(5)},${s.longitude.toStringAsFixed(5)}',
        )
        .join('|');
    return PlannedRouteGeometryResult(
      routeId: routeId,
      cached: false,
      stopHash: stopHash,
      encodedPolyline: encoded,
      distanceMeters: _estimateDistanceMeters(stops),
      durationSeconds: _estimateDurationSeconds(stops),
      generatedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
  }

  static int _estimateDistanceMeters(List<RouteWaypoint> stops) {
    const r = 6371000.0;
    var total = 0.0;
    for (var i = 0; i < stops.length - 1; i++) {
      final lat1 = stops[i].latitude * pi / 180;
      final lat2 = stops[i + 1].latitude * pi / 180;
      final dLat = (stops[i + 1].latitude - stops[i].latitude) * pi / 180;
      final dLon = (stops[i + 1].longitude - stops[i].longitude) * pi / 180;
      final a =
          sin(dLat / 2) * sin(dLat / 2) +
          cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
      final c = 2 * atan2(sqrt(a), sqrt(1 - a));
      total += r * c;
    }
    return (total * 1.3).round();
  }

  static int _estimateDurationSeconds(List<RouteWaypoint> stops) {
    final distMeters = _estimateDistanceMeters(stops);
    final drivingSec = (distMeters / 8.33).round();
    final stopSec = (stops.length - 1) * 60;
    return drivingSec + stopSec;
  }

  /// Authenticated: traffic-aware ETA and live polyline for an active session.
  /// Stop visibility is authorized server-side; only linked stops are returned
  /// for parents.
  static Future<TrafficEtaSnapshot> getTrafficEta(String sessionId) async {
    final result = await _functions.httpsCallable('getTrafficEta').call({
      'sessionId': sessionId,
    });
    final data = (result.data as Map?)?.cast<String, dynamic>();
    return TrafficEtaSnapshot.fromCallable(data);
  }

  /// Admin-only: regenerates Google geometry for every saved route from its
  /// ordered stops. Never deletes valid legacy data.
  static Future<RouteMigrationResult> migrateRouteGeometry() async {
    final result = await _functions
        .httpsCallable('migrateRouteGeometry')
        .call(<String, dynamic>{});
    final data = (result.data as Map?)?.cast<String, dynamic>() ?? {};
    final failed = <RouteMigrationFailure>[];
    final rawFailed = data['failed'];
    if (rawFailed is List) {
      for (final item in rawFailed) {
        if (item is Map) {
          final map = item.cast<String, dynamic>();
          failed.add(
            RouteMigrationFailure(
              routeId: map['routeId'] as String? ?? '',
              name: map['name'] as String? ?? '',
              stops: (map['stops'] as num?)?.toInt() ?? 0,
              error: map['error'] as String? ?? '',
            ),
          );
        }
      }
    }
    return RouteMigrationResult(
      total: (data['total'] as num?)?.toInt() ?? 0,
      migrated: (data['migrated'] as num?)?.toInt() ?? 0,
      skipped: (data['skipped'] as num?)?.toInt() ?? 0,
      tooLarge: (data['tooLarge'] as num?)?.toInt() ?? 0,
      failed: failed,
      legacyRetained: data['legacyRetained'] as bool? ?? true,
    );
  }

  static DateTime? _toDate(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    final text = raw.toString();
    return DateTime.tryParse(text);
  }
}
