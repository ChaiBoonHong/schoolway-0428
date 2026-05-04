import 'package:cloud_firestore/cloud_firestore.dart';

class RouteSession {
  final String id;
  final String driverId;
  final String busId;
  final String? routeId;
  final DateTime startTime;
  final DateTime? endTime;
  final String status; // 'Active', 'Completed'
  final bool gpsTrackingEnabled;

  RouteSession({
    required this.id,
    required this.driverId,
    required this.busId,
    this.routeId,
    required this.startTime,
    this.endTime,
    required this.status,
    required this.gpsTrackingEnabled,
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
    };
  }
}

