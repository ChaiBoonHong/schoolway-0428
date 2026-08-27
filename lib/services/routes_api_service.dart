import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
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

  /// Injectable callable override for unit testing.
  @visibleForTesting
  static Future<Map<String, dynamic>> Function(
    String name,
    Map<String, dynamic> parameters,
  )?
  callableOverride;

  /// Admin-only: computes (and caches for 30 days) Google DRIVE geometry for
  /// an ordered stop plan. Throws when Google geometry computation fails;
  /// never fabricates fake road geometry.
  static Future<PlannedRouteGeometryResult> computePlannedRoute({
    String? routeId,
    required List<RouteWaypoint> stops,
    FirebaseFunctions? functions,
  }) async {
    if (stops.length < 2) {
      throw ArgumentError('At least two stops are required.');
    }
    if (stops.length > 26) {
      throw ArgumentError('At most 26 stops are supported.');
    }
    final params = {
      if (routeId != null && routeId.isNotEmpty) 'routeId': routeId,
      'stops': stops.map((stop) => stop.toMap()).toList(),
    };
    final Map<String, dynamic> data;
    if (callableOverride != null) {
      data = await callableOverride!('computePlannedRoute', params);
    } else {
      final targetFunctions = functions ?? _functions;
      final result = await targetFunctions
          .httpsCallable('computePlannedRoute')
          .call(params);
      data = (result.data as Map?)?.cast<String, dynamic>() ?? {};
    }
    final polyline = data['encodedPolyline'] as String? ?? '';
    if (polyline.isEmpty) {
      throw StateError('Google Routes API returned no valid route geometry.');
    }
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
