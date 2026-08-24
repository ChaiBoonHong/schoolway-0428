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

  int get serviceStopNumber => tripOrderIndex + 1;

  String get label => 'Stop $serviceStopNumber';
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
  List<int> serviceStopRouteIndices = const [],
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

  final indices = serviceStopRouteIndices.isNotEmpty
      ? List<int>.from(serviceStopRouteIndices)
      : (grouped.keys.toList()..sort());
  if (serviceStopRouteIndices.isEmpty &&
      direction == TripDirection.fromSchool) {
    indices.setAll(0, indices.reversed.toList());
  }

  return [
    for (var tripIndex = 0; tripIndex < indices.length; tripIndex++)
      if (indices[tripIndex] >= 0 &&
          indices[tripIndex] < routeStops.length &&
          grouped.containsKey(indices[tripIndex]))
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
