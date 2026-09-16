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

int? studentStopIndex(Student student, TripDirection direction) {
  if (direction == TripDirection.fromSchool) {
    return student.dropoffStopIndex ?? student.pickupStopIndex;
  }
  return student.pickupStopIndex;
}

int? etaMinutesForStudents({
  required Iterable<Student> students,
  required TripDirection direction,
  required Iterable<TrafficStopEta> stopEtas,
}) {
  final etaByRouteStop = {
    for (final eta in stopEtas) eta.routeStopIndex: eta.etaMinutes,
  };
  int? nearestEta;
  for (final student in students) {
    final routeStopIndex = studentStopIndex(student, direction);
    final etaMinutes = routeStopIndex == null
        ? null
        : etaByRouteStop[routeStopIndex];
    if (etaMinutes != null && (nearestEta == null || etaMinutes < nearestEta)) {
      nearestEta = etaMinutes;
    }
  }
  return nearestEta;
}

int? etaSecondsForStudents({
  required Iterable<Student> students,
  required TripDirection direction,
  required Iterable<TrafficStopEta> stopEtas,
}) {
  final etaByRouteStop = {
    for (final eta in stopEtas)
      eta.routeStopIndex: eta.etaSeconds ?? eta.etaMinutes * 60,
  };
  int? nearestEta;
  for (final student in students) {
    final routeStopIndex = studentStopIndex(student, direction);
    final etaSeconds = routeStopIndex == null
        ? null
        : etaByRouteStop[routeStopIndex];
    if (etaSeconds != null && (nearestEta == null || etaSeconds < nearestEta)) {
      nearestEta = etaSeconds;
    }
  }
  return nearestEta;
}

/// Whether a parent has at least one child currently onboard in [events] for
/// the active route session. The most recent event wins for each child.
bool hasOnboardStudent({
  required Iterable<Student> students,
  required Iterable<BoardingEvent> events,
}) {
  final childIds = students.map((student) => student.id).toSet();
  final latestByStudent = <String, BoardingEvent>{};
  for (final event in events) {
    if (!childIds.contains(event.studentId)) continue;
    final previous = latestByStudent[event.studentId];
    if (previous == null ||
        event.timestamp.isAfter(previous.timestamp) ||
        (event.timestamp == previous.timestamp &&
            event.id.compareTo(previous.id) > 0)) {
      latestByStudent[event.studentId] = event;
    }
  }
  return latestByStudent.values.any((event) {
    final type = event.eventType.trim().toLowerCase();
    return type == 'board' || type == 'boarded';
  });
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
