import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/eta_geofence_service.dart';

void main() {
  const route = <RouteWaypoint>[
    RouteWaypoint(latitude: 0, longitude: 0),
    RouteWaypoint(latitude: 0, longitude: 0.01),
    RouteWaypoint(latitude: 0.01, longitude: 0.01),
  ];

  test('ETA follows saved road geometry instead of a straight line', () {
    final eta = EtaGeofenceService.calculateRouteEtaMinutes(
      currentPos: const LatLng(0, 0.005),
      routeWaypoints: route,
      targetStop: route.last,
      speedKmh: 60,
    );

    expect(eta, 2);
  });

  test('target already behind the bus does not produce a forward ETA', () {
    final eta = EtaGeofenceService.calculateRouteEtaMinutes(
      currentPos: const LatLng(0.005, 0.01),
      routeWaypoints: route,
      targetStop: route.first,
      speedKmh: 30,
    );

    expect(eta, isNull);
  });

  test('speed smoothing records each timestamp once', () {
    final first = EtaGeofenceService.smoothedSpeedKmh(
      key: 'eta-test',
      speedKmh: 20,
      sampledAt: DateTime(2026, 1, 1, 8),
    );
    final duplicate = EtaGeofenceService.smoothedSpeedKmh(
      key: 'eta-test',
      speedKmh: 100,
      sampledAt: DateTime(2026, 1, 1, 8),
    );
    final second = EtaGeofenceService.smoothedSpeedKmh(
      key: 'eta-test',
      speedKmh: 40,
      sampledAt: DateTime(2026, 1, 1, 8, 0, 3),
    );

    expect(first, 20);
    expect(duplicate, 20);
    expect(second, 30);
    EtaGeofenceService.clearSession('eta-test');
  });
}
