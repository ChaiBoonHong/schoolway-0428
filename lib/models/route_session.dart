import 'package:cloud_firestore/cloud_firestore.dart';

/// Driver leg: map pins and polyline follow planned order (to school) or reverse it (from school).
enum TripDirection {
  toSchool,
  fromSchool,
}

TripDirection tripDirectionFromFirestore(Object? raw) {
  final s = raw?.toString().trim().toLowerCase() ?? '';
  if (s == 'fromschool') return TripDirection.fromSchool;
  return TripDirection.toSchool;
}

String tripDirectionToFirestore(TripDirection d) {
  switch (d) {
    case TripDirection.fromSchool:
      return 'fromSchool';
    case TripDirection.toSchool:
      return 'toSchool';
  }
}

class RouteSession {
  final String id;
  final String driverId;
  final String busId;
  final String? routeId;
  final DateTime startTime;
  final DateTime? endTime;
  final String status; // 'Active', 'Completed'
  final bool gpsTrackingEnabled;
  final TripDirection tripDirection;

  RouteSession({
    required this.id,
    required this.driverId,
    required this.busId,
    this.routeId,
    required this.startTime,
    this.endTime,
    required this.status,
    required this.gpsTrackingEnabled,
    this.tripDirection = TripDirection.toSchool,
  });

  bool get isActive => status == 'Active';

  factory RouteSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RouteSession(
      id: doc.id,
      driverId: data['driverId'] ?? '',
      busId: data['busId'] ?? '',
      routeId: data['routeId'],
      startTime: (data['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endTime: (data['endTime'] as Timestamp?)?.toDate(),
      status: data['status'] ?? 'Active',
      gpsTrackingEnabled: data['gpsTrackingEnabled'] ?? false,
      tripDirection: tripDirectionFromFirestore(data['tripDirection']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'driverId': driverId,
      'busId': busId,
      'routeId': routeId,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': endTime != null ? Timestamp.fromDate(endTime!) : null,
      'status': status,
      'gpsTrackingEnabled': gpsTrackingEnabled,
      'tripDirection': tripDirectionToFirestore(tripDirection),
    };
  }
}

