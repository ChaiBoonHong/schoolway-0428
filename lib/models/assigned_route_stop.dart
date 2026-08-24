import 'package:schoolway/models/models.dart';

class AssignedRouteStop {
  const AssignedRouteStop({
    required this.routeStopIndex,
    required this.tripOrderIndex,
    required this.waypoint,
    required this.students,
  });

  final int routeStopIndex;
  final int tripOrderIndex;
  final RouteWaypoint waypoint;
  final List<Student> students;

  String get label => 'Stop ${routeStopIndex + 1}';
}

final RegExp _stopIndexPattern = RegExp(
  r'^Stop\s+(\d+)\b',
  caseSensitive: false,
);

int? _legacyStopIndex(String? label) {
  final match = _stopIndexPattern.firstMatch(label?.trim() ?? '');
  final oneBased = int.tryParse(match?.group(1) ?? '');
  return oneBased == null || oneBased < 1 ? null : oneBased - 1;
}

int? studentStopIndex(Student student, TripDirection direction) {
  if (direction == TripDirection.fromSchool) {
    return student.dropoffStopIndex ?? _legacyStopIndex(student.dropoffStop);
  }
  return student.pickupStopIndex ?? _legacyStopIndex(student.pickupStop);
}

List<AssignedRouteStop> buildAssignedRouteStops({
  required PlannedRoute route,
  required String busId,
  required TripDirection direction,
  required Iterable<Student> students,
}) {
  final routeStops = route.editableStops;
  final grouped = <int, List<Student>>{};

  for (final student in students) {
    if (student.status.toLowerCase() != 'active' ||
        student.assignedBusId != busId ||
        student.assignedRouteId != route.id) {
      continue;
    }
    final index = studentStopIndex(student, direction);
    if (index == null || index < 0 || index >= routeStops.length) continue;
    grouped.putIfAbsent(index, () => <Student>[]).add(student);
  }

  final indices = grouped.keys.toList()..sort();
  if (direction == TripDirection.fromSchool) {
    indices.setAll(0, indices.reversed.toList());
  }

  return [
    for (var tripIndex = 0; tripIndex < indices.length; tripIndex++)
      AssignedRouteStop(
        routeStopIndex: indices[tripIndex],
        tripOrderIndex: tripIndex,
        waypoint: routeStops[indices[tripIndex]],
        students: List<Student>.unmodifiable(
          grouped[indices[tripIndex]]!
            ..sort((a, b) => a.fullName.compareTo(b.fullName)),
        ),
      ),
  ];
}
