import 'package:cloud_firestore/cloud_firestore.dart';

class GpsTracking {
  final String busId; // Document ID is busId
  final double latitude;
  final double longitude;
  final double speed; // km/h
  final double heading; // degrees
  final double accuracy; // meters
  final DateTime timestamp;
  final String? sessionId;

  GpsTracking({
    required this.busId,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.heading,
    required this.accuracy,
    required this.timestamp,
    this.sessionId,
  });

  factory GpsTracking.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GpsTracking(
      busId: doc.id,
      latitude: data['latitude']?.toDouble() ?? 0.0,
      longitude: data['longitude']?.toDouble() ?? 0.0,
      speed: data['speed']?.toDouble() ?? 0.0,
      heading: data['heading']?.toDouble() ?? 0.0,
      accuracy: data['accuracy']?.toDouble() ?? 0.0,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      sessionId: data['sessionId'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'speed': speed,
      'heading': heading,
      'accuracy': accuracy,
      'timestamp': Timestamp.fromDate(timestamp),
      'sessionId': sessionId,
    };
  }

  String getLastSeenText() {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min${difference.inMinutes == 1 ? '' : 's'} ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    }
  }
}

