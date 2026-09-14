import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/eta_geofence_service.dart';

void main() {
  test('distance from route distinguishes inside and outside corridor', () {
    const route = [
      RouteWaypoint(latitude: 3.1000, longitude: 101.1000),
      RouteWaypoint(latitude: 3.1100, longitude: 101.1000),
    ];
    final near = EtaGeofenceService.distanceFromRouteMeters(
      currentLocation: const LatLng(3.1050, 101.1005),
      routeWaypoints: route,
    );
    final far = EtaGeofenceService.distanceFromRouteMeters(
      currentLocation: const LatLng(3.1050, 101.1100),
      routeWaypoints: route,
    );
    expect(near, lessThan(100));
    expect(far, greaterThan(1000));
  });

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

  test(
    'processLocationUpdate handles arrival, departure, and stop transition',
    () async {
      final stops = [
        AssignedRouteStop(
          routeStopIndex: 0,
          tripOrderIndex: 0,
          waypoint: const RouteWaypoint(latitude: 3.1000, longitude: 101.1000),
          students: const [],
        ),
        AssignedRouteStop(
          routeStopIndex: 1,
          tripOrderIndex: 1,
          waypoint: const RouteWaypoint(latitude: 3.1030, longitude: 101.1000),
          students: const [],
        ),
      ];

      EtaGeofenceService.clearSession('session-test');

      // 1. Bus arrives at Stop 1 (within 50m of stop 0)
      final arrivalStop1 = await EtaGeofenceService.processLocationUpdate(
        sessionId: 'session-test',
        busId: 'bus-1',
        driverUid: 'driver-1',
        currentPos: const LatLng(3.1001, 101.1000),
        stops: stops,
      );
      expect(arrivalStop1, isNotNull);
      expect(arrivalStop1!.type, GeofenceEventType.atStop);
      expect(arrivalStop1.stopIndex, 0);
      expect(EtaGeofenceService.currentStopIndexForSession('session-test'), 0);
      expect(
        EtaGeofenceService.currentStopForSession(
          'session-test',
          stops,
        )?.routeStopIndex,
        0,
      );

      // 2. Bus remains at Stop 1 (no duplicate events)
      final sameStop = await EtaGeofenceService.processLocationUpdate(
        sessionId: 'session-test',
        busId: 'bus-1',
        driverUid: 'driver-1',
        currentPos: const LatLng(3.1002, 101.1000),
        stops: stops,
      );
      expect(sameStop, isNull);

      // 3. Bus transitions to Stop 2 (~333m away, within 50m of stop 1)
      final arrivalStop2 = await EtaGeofenceService.processLocationUpdate(
        sessionId: 'session-test',
        busId: 'bus-1',
        driverUid: 'driver-1',
        currentPos: const LatLng(3.1031, 101.1000),
        stops: stops,
      );
      expect(arrivalStop2, isNotNull);
      expect(arrivalStop2!.type, GeofenceEventType.atStop);
      expect(arrivalStop2.stopIndex, 1);
      expect(EtaGeofenceService.currentStopIndexForSession('session-test'), 1);

      // 4. Bus departs Stop 2 (moves > 250m away from Stop 2)
      final departureStop2 = await EtaGeofenceService.processLocationUpdate(
        sessionId: 'session-test',
        busId: 'bus-1',
        driverUid: 'driver-1',
        currentPos: const LatLng(3.1070, 101.1000),
        stops: stops,
      );
      expect(departureStop2, isNotNull);
      expect(departureStop2!.type, GeofenceEventType.departedStop);
      expect(departureStop2.stopIndex, 1);
      expect(
        EtaGeofenceService.currentStopIndexForSession('session-test'),
        isNull,
      );

      EtaGeofenceService.clearSession('session-test');
    },
  );
}
