import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/models/models.dart';

void main() {
  final route = PlannedRoute(
    id: 'route-1',
    name: 'Route 1',
    stops: List.generate(
      8,
      (index) => RouteWaypoint(
        latitude: 3.0 + index / 100,
        longitude: 101.0 + index / 100,
      ),
    ),
    waypoints: const [],
    createdAt: DateTime(2026),
  );

  Student student(int number, int stopIndex, {String status = 'Active'}) {
    return Student(
      id: 'student-$number',
      studentId: 'S$number',
      firstName: 'Student',
      lastName: '$number',
      nfcCardId: 'NFC$number',
      parentAuthUids: const [],
      assignedBusId: 'bus-001',
      assignedRouteId: 'route-1',
      pickupStopIndex: stopIndex,
      dropoffStopIndex: stopIndex,
      status: status,
      createdAt: DateTime(2026),
    );
  }

  test('two students sharing one stop produce seven map points', () {
    final students = [
      student(1, 0),
      student(2, 0),
      for (var i = 3; i <= 8; i++) student(i, i - 2),
    ];

    final stops = buildAssignedRouteStops(
      route: route,
      busId: 'bus-001',
      direction: TripDirection.toSchool,
      students: students,
    );

    expect(stops, hasLength(7));
    expect(stops.first.students, hasLength(2));
  });

  test('three students sharing one stop produce six map points', () {
    final students = [
      student(1, 0),
      student(2, 0),
      student(3, 0),
      for (var i = 4; i <= 8; i++) student(i, i - 3),
    ];

    final stops = buildAssignedRouteStops(
      route: route,
      busId: 'bus-001',
      direction: TripDirection.toSchool,
      students: students,
    );

    expect(stops, hasLength(6));
    expect(stops.first.students, hasLength(3));
  });

  test('drop-off stops are ordered in reverse route direction', () {
    final stops = buildAssignedRouteStops(
      route: route,
      busId: 'bus-001',
      direction: TripDirection.fromSchool,
      students: [student(1, 1), student(2, 6)],
    );

    expect(stops.map((stop) => stop.routeStopIndex), [6, 1]);
    expect(stops.map((stop) => stop.serviceStopNumber), [1, 2]);
    expect(stops.map((stop) => stop.label), ['Stop 1', 'Stop 2']);
  });

  test('sparse route points are renumbered as consecutive service stops', () {
    final longRoute = PlannedRoute(
      id: 'route-1',
      name: 'Long route',
      stops: List.generate(
        16,
        (index) => RouteWaypoint(
          latitude: 3 + index / 100,
          longitude: 101 + index / 100,
        ),
      ),
      waypoints: const [],
      createdAt: DateTime(2026),
    );
    final stops = buildAssignedRouteStops(
      route: longRoute,
      busId: 'bus-001',
      direction: TripDirection.toSchool,
      students: [student(1, 9), student(2, 11), student(3, 13), student(4, 15)],
    );

    expect(stops.map((stop) => stop.routeStopIndex), [9, 11, 13, 15]);
    expect(stops.map((stop) => stop.label), [
      'Stop 1',
      'Stop 2',
      'Stop 3',
      'Stop 4',
    ]);
  });

  test(
    'session snapshot preserves bus-wide numbering for a filtered roster',
    () {
      final stops = buildAssignedRouteStops(
        route: route,
        busId: 'bus-001',
        direction: TripDirection.toSchool,
        students: [student(1, 6)],
        serviceStopRouteIndices: const [1, 3, 5, 6],
      );

      expect(stops, hasLength(1));
      expect(stops.single.routeStopIndex, 6);
      expect(stops.single.tripOrderIndex, 3);
      expect(stops.single.label, 'Stop 4');
    },
  );

  test('inactive, unrelated, and invalid assignments are excluded', () {
    final unrelated = student(2, 1);
    final invalid = Student(
      id: 'invalid',
      studentId: 'invalid',
      firstName: 'Invalid',
      lastName: 'Stop',
      nfcCardId: 'invalid',
      parentAuthUids: const [],
      assignedBusId: 'bus-001',
      assignedRouteId: 'route-1',
      pickupStopIndex: 99,
      status: 'Active',
      createdAt: DateTime(2026),
    );

    final stops = buildAssignedRouteStops(
      route: route,
      busId: 'other-bus',
      direction: TripDirection.toSchool,
      students: [
        student(1, 0, status: 'Inactive'),
        unrelated,
        invalid,
      ],
    );

    expect(stops, isEmpty);
  });
}
