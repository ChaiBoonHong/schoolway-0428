import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/models/models.dart';

RouteWaypoint _stop(double lat) =>
    RouteWaypoint(latitude: lat, longitude: 101.13);

List<RouteWaypoint> _stops(int count) =>
    List.generate(count, (i) => _stop(4.30 + i * 0.001));

void main() {
  group('planRouteSplit', () {
    test('splits with a shared junction stop keeping parts connected', () {
      final stops = _stops(27);
      final plan = planRouteSplit(stops, 15);
      expect(plan, isNotNull);
      expect(plan!.first.length, 15);
      expect(plan.second.length, 13);
      expect(plan.first.last.latitude, stops[14].latitude);
      expect(plan.second.first.latitude, stops[14].latitude);
    });

    test('splits without sharing into disjoint parts', () {
      final stops = _stops(10);
      final plan = planRouteSplit(stops, 5, shareJunctionStop: false);
      expect(plan, isNotNull);
      expect(plan!.first.length, 5);
      expect(plan.second.length, 5);
      expect(plan.first.last.latitude, stops[4].latitude);
      expect(plan.second.first.latitude, stops[5].latitude);
    });

    test('preserves full stop order across both parts', () {
      final stops = _stops(27);
      final plan = planRouteSplit(stops, 15);
      final combined = [...plan!.first, ...plan.second.skip(1)];
      for (var i = 0; i < stops.length; i++) {
        expect(combined[i].latitude, stops[i].latitude);
      }
    });

    test('rejects plans with fewer than two stops per part', () {
      expect(planRouteSplit(_stops(3), 1), isNull);
      expect(planRouteSplit(_stops(3), 2, shareJunctionStop: false), isNull);
      expect(planRouteSplit(_stops(4), 3, shareJunctionStop: false), isNull);
    });

    test('shared junction keeps a minimal three-stop split drivable', () {
      final plan = planRouteSplit(_stops(3), 2);
      expect(plan, isNotNull);
      expect(plan!.first.length, 2);
      expect(plan.second.length, 2);
    });

    test('rejects out-of-range split positions', () {
      expect(planRouteSplit(_stops(10), 0), isNull);
      expect(planRouteSplit(_stops(10), 10), isNull);
      expect(planRouteSplit(_stops(10), -1), isNull);
    });

    test('rejects parts exceeding the Google stop limit', () {
      // 30 stops: any split leaves one part above 26.
      expect(planRouteSplit(_stops(30), 2), isNull);
      expect(planRouteSplit(_stops(30), 27, shareJunctionStop: false), isNull);
    });

    test('accepts the largest valid shared-junction split', () {
      final stops = _stops(27);
      final plan = planRouteSplit(stops, 2);
      expect(plan, isNotNull);
      expect(plan!.first.length, 2);
      expect(plan.second.length, 26);
    });

    test('maps original indices onto parts with a shared junction', () {
      final plan = planRouteSplit(_stops(27), 15)!;
      expect(plan.positionOfOriginal(0), (0, 0));
      expect(plan.positionOfOriginal(14), (0, 14));
      expect(plan.positionOfOriginal(15), (1, 1));
      expect(plan.positionOfOriginal(26), (1, 12));
      expect(plan.positionOfOriginal(27), isNull);
      expect(plan.positionOfOriginal(-1), isNull);
    });

    test('maps original indices without a shared junction', () {
      final plan = planRouteSplit(_stops(10), 5, shareJunctionStop: false)!;
      expect(plan.positionOfOriginal(4), (0, 4));
      expect(plan.positionOfOriginal(5), (1, 0));
      expect(plan.positionOfOriginal(9), (1, 4));
      // Junction ownership stays with part one when shared.
      final shared = planRouteSplit(_stops(10), 5)!;
      expect(shared.positionOfOriginal(4), (0, 4));
    });
  });
}
