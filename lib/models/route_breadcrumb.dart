import 'package:cloud_firestore/cloud_firestore.dart';

class RouteBreadcrumb {
  final String id;
  final double latitude;
  final double longitude;
  final double speed;
  final DateTime timestamp;

  RouteBreadcrumb({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.timestamp,
  });

  factory RouteBreadcrumb.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return RouteBreadcrumb(
      id: doc.id,
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
      speed: (data['speed'] as num?)?.toDouble() ?? 0.0,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'speed': speed,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
