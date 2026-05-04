import 'package:cloud_firestore/cloud_firestore.dart';

class BoardingEvent {
  final String id;
  final String studentId;
  final String busId;
  final String driverId;
  final String? sessionId;
  final String eventType; // 'board' / 'alight' (legacy: Boarded / Drop off)
  final EventLocation location;
  final DateTime timestamp;
  final String? nfcCardId;
  final bool synced;

  BoardingEvent({
    required this.id,
    required this.studentId,
    required this.busId,
    required this.driverId,
    this.sessionId,
    required this.eventType,
    required this.location,
    required this.timestamp,
    this.nfcCardId,
    required this.synced,
  });

  factory BoardingEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BoardingEvent(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      busId: data['busId'] ?? '',
      driverId: data['driverId'] ?? '',
      sessionId: data['sessionId'],
      eventType: data['eventType'] ?? 'board',
      location: EventLocation.fromMap(data['location'] ?? {}),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      nfcCardId: data['nfcCardId'],
      synced: data['synced'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'studentId': studentId,
      'busId': busId,
      'driverId': driverId,
      'sessionId': sessionId,
      'eventType': eventType,
      'location': location.toMap(),
      'timestamp': Timestamp.fromDate(timestamp),
      'nfcCardId': nfcCardId,
      'synced': synced,
    };
  }
}

class EventLocation {
  final String name;
  final double latitude;
  final double longitude;

  EventLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  factory EventLocation.fromMap(Map<String, dynamic> map) {
    return EventLocation(
      name: map['name'] ?? '',
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  /// True when lat/lng look like a real GPS fix (not the Unknown placeholder 0,0).
  bool get hasValidCoordinates {
    if (!latitude.isFinite || !longitude.isFinite) return false;
    if (latitude == 0.0 && longitude == 0.0) return false;
    if (latitude.abs() > 90 || longitude.abs() > 180) return false;
    return true;
  }
}

