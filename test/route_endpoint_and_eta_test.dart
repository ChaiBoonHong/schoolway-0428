import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/models/models.dart';

void main() {
  const school = RouteWaypoint(latitude: 4.3320, longitude: 101.1410);
  const stop1 = RouteWaypoint(latitude: 4.3100, longitude: 101.1200);
  const stop2 = RouteWaypoint(latitude: 4.3200, longitude: 101.1300);

  group('ensureSchoolRouteEndpoint', () {
    test('appends school to empty list', () {
      final result = ensureSchoolRouteEndpoint(const [], school);
      expect(result.length, 1);
      expect(result.first.latitude, school.latitude);
      expect(result.first.longitude, school.longitude);
    });

    test('appends school when final stop is not near school', () {
      final stops = [stop1, stop2];
      final result = ensureSchoolRouteEndpoint(stops, school);

      expect(result.length, 3);
      // Existing student stop indices preserved
      expect(result[0].latitude, stop1.latitude);
      expect(result[0].longitude, stop1.longitude);
      expect(result[1].latitude, stop2.latitude);
      expect(result[1].longitude, stop2.longitude);
      // School appended as final endpoint
      expect(result[2].latitude, school.latitude);
      expect(result[2].longitude, school.longitude);
    });

    test('normalizes endpoint when already near school', () {
      // Near school within 10 meters
      const nearSchool = RouteWaypoint(
        latitude: 4.332001,
        longitude: 101.141001,
      );
      final stops = [stop1, nearSchool];
      final result = ensureSchoolRouteEndpoint(stops, school);

      expect(result.length, 2);
      expect(result[0].latitude, stop1.latitude);
      expect(result[1].latitude, school.latitude);
      expect(result[1].longitude, school.longitude);
    });
  });

  group('PlannedRoute trip order and reversal', () {
    final route = PlannedRoute(
      id: 'test-route-1',
      name: 'Main Route',
      stops: const [stop1, stop2, school],
      waypoints: const [stop1, stop2, school],
      createdAt: DateTime.utc(2026),
    );

    test('toSchool trip ends at school endpoint', () {
      final tripStops = route.editableStopsForTrip(TripDirection.toSchool);
      expect(tripStops.length, 3);
      expect(tripStops.first.latitude, stop1.latitude);
      expect(tripStops.last.latitude, school.latitude);
    });

    test(
      'fromSchool trip reverses stops starting at school and finishing at stop 1',
      () {
        final tripStops = route.editableStopsForTrip(TripDirection.fromSchool);
        expect(tripStops.length, 3);
        expect(tripStops.first.latitude, school.latitude);
        expect(tripStops.last.latitude, stop1.latitude);
      },
    );
  });

  group('route stop limits', () {
    test('planned route stop limit is 26 including school endpoint', () {
      expect(maxPlannedRouteStops, 26);
      final stops = List.generate(
        25,
        (i) => RouteWaypoint(latitude: 4.30 + i * 0.001, longitude: 101.13),
      );
      final withSchool = ensureSchoolRouteEndpoint(stops, school);
      expect(withSchool.length, 26);
      expect(withSchool.length <= maxPlannedRouteStops, isTrue);

      final overLimit = List.generate(
        26,
        (i) => RouteWaypoint(latitude: 4.30 + i * 0.001, longitude: 101.13),
      );
      final overWithSchool = ensureSchoolRouteEndpoint(overLimit, school);
      expect(overWithSchool.length, 27);
      expect(overWithSchool.length > maxPlannedRouteStops, isTrue);
    });
  });
}
