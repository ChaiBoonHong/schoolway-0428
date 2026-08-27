import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/routes_api_service.dart';

void main() {
  tearDown(() {
    RoutesApiService.callableOverride = null;
  });

  group('RoutesApiService.computePlannedRoute', () {
    test('rejects fewer than 2 stops with ArgumentError', () async {
      expect(
        () => RoutesApiService.computePlannedRoute(
          stops: [const RouteWaypoint(latitude: 3.1, longitude: 101.6)],
        ),
        throwsArgumentError,
      );
    });

    test('rejects more than 26 stops with ArgumentError', () async {
      final manyStops = List.generate(
        27,
        (i) => RouteWaypoint(latitude: 3.0 + i * 0.01, longitude: 101.0),
      );
      expect(
        () => RoutesApiService.computePlannedRoute(stops: manyStops),
        throwsArgumentError,
      );
    });

    test(
      'returns valid PlannedRouteGeometryResult on successful Google computation',
      () async {
        final now = DateTime.now();
        RoutesApiService.callableOverride = (name, params) async {
          expect(name, 'computePlannedRoute');
          expect(params['routeId'], 'route_123');
          expect((params['stops'] as List).length, 2);
          return {
            'routeId': 'route_123',
            'cached': true,
            'stopHash': 'hash_abc',
            'encodedPolyline': '_p~iF~ps|U_ulLnnqC',
            'distanceMeters': 1250,
            'durationSeconds': 180,
            'generatedAt': now.toIso8601String(),
            'expiresAt': now.add(const Duration(days: 30)).toIso8601String(),
          };
        };

        final result = await RoutesApiService.computePlannedRoute(
          routeId: 'route_123',
          stops: const [
            RouteWaypoint(latitude: 3.1, longitude: 101.6),
            RouteWaypoint(latitude: 3.2, longitude: 101.7),
          ],
        );

        expect(result.routeId, 'route_123');
        expect(result.cached, isTrue);
        expect(result.stopHash, 'hash_abc');
        expect(result.encodedPolyline, '_p~iF~ps|U_ulLnnqC');
        expect(result.distanceMeters, 1250);
        expect(result.durationSeconds, 180);
      },
    );

    test('throws StateError when backend returns empty polyline', () async {
      RoutesApiService.callableOverride = (name, params) async {
        return {'routeId': 'route_123', 'encodedPolyline': ''};
      };

      expect(
        () => RoutesApiService.computePlannedRoute(
          stops: const [
            RouteWaypoint(latitude: 3.1, longitude: 101.6),
            RouteWaypoint(latitude: 3.2, longitude: 101.7),
          ],
        ),
        throwsStateError,
      );
    });

    test(
      'propagates callable exceptions and never returns a fake direct route',
      () async {
        RoutesApiService.callableOverride = (name, params) async {
          throw Exception('Cloud Functions callable network failure');
        };

        expect(
          () => RoutesApiService.computePlannedRoute(
            stops: const [
              RouteWaypoint(latitude: 3.1, longitude: 101.6),
              RouteWaypoint(latitude: 3.2, longitude: 101.7),
            ],
          ),
          throwsA(isA<Exception>()),
        );
      },
    );
  });
}
