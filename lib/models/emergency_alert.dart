import 'package:cloud_firestore/cloud_firestore.dart';

class EmergencyAlert {
  final String id;
  final String driverUid;
  final String busId;
  final String? sessionId;
  final AlertLocation location;
  final DateTime timestamp;
  final String status; // 'Active', 'Resolved'
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final int parentsNotifiedCount;
  final List<EmergencyNotificationRecipient> notifiedParents;

  EmergencyAlert({
    required this.id,
    required this.driverUid,
    required this.busId,
    this.sessionId,
    required this.location,
    required this.timestamp,
    required this.status,
    this.resolvedBy,
    this.resolvedAt,
    this.parentsNotifiedCount = 0,
    this.notifiedParents = const [],
  });

  bool get isActive => status == 'Active';

  factory EmergencyAlert.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EmergencyAlert(
      id: doc.id,
      driverUid: data['driverUid'] ?? '',
      busId: data['busId'] ?? '',
      sessionId: data['sessionId'],
      location: AlertLocation.fromMap(data['location'] ?? {}),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: data['status'] ?? 'Active',
      resolvedBy: data['resolvedBy'],
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      parentsNotifiedCount: data['parentsNotifiedCount'] as int? ?? 0,
      notifiedParents: (data['notifiedParents'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => EmergencyNotificationRecipient.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'driverUid': driverUid,
      'busId': busId,
      'location': location.toMap(),
      'timestamp': Timestamp.fromDate(timestamp),
      'status': status,
      'parentsNotifiedCount': parentsNotifiedCount,
      'notifiedParents': notifiedParents
          .map((parent) => parent.toMap())
          .toList(),
    };
    if (sessionId != null) map['sessionId'] = sessionId;
    if (resolvedBy != null) map['resolvedBy'] = resolvedBy;
    if (resolvedAt != null) {
      map['resolvedAt'] = Timestamp.fromDate(resolvedAt!);
    }
    return map;
  }
}

class EmergencyNotificationRecipient {
  final String authUid;
  final String username;
  final String name;

  const EmergencyNotificationRecipient({
    required this.authUid,
    required this.username,
    required this.name,
  });

  factory EmergencyNotificationRecipient.fromMap(Map<String, dynamic> map) {
    return EmergencyNotificationRecipient(
      authUid: map['authUid'] as String? ?? '',
      username: map['username'] as String? ?? '',
      name: map['name'] as String? ?? '',
    );
  }

  Map<String, String> toMap() => {
    'authUid': authUid,
    'username': username,
    'name': name,
  };
}

class AlertLocation {
  final double latitude;
  final double longitude;

  AlertLocation({required this.latitude, required this.longitude});

  factory AlertLocation.fromMap(Map<String, dynamic> map) {
    return AlertLocation(
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {'latitude': latitude, 'longitude': longitude};
  }
}
