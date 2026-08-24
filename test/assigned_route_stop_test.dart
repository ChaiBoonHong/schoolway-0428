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
      pickupStop: 'Stop ${stopIndex + 1}',
      pickupStopIndex: stopIndex,
      dropoffStop: 'Stop ${stopIndex + 1}',
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
  });

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
      pickupStop: 'Unknown',
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
