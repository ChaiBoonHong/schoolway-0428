import 'package:cloud_firestore/cloud_firestore.dart';

class Bus {
  final String id;
  final String busNumber;
  final String licensePlate;
  final String status; // 'Active', 'Idle', 'Maintenance'
  final String? currentDriverUid;

  /// Display name; kept in sync when [assignedRouteId] is set.
  final String? currentRoute;

  /// Firestore `planned_routes` document id (one planned route per bus).
  final String? assignedRouteId;
  final int capacity;
  final BusLocation? lastLocation;
  final DateTime createdAt;

  Bus({
    required this.id,
    required this.busNumber,
    required this.licensePlate,
    required this.status,
    this.currentDriverUid,
    this.currentRoute,
    this.assignedRouteId,
    required this.capacity,
    this.lastLocation,
    required this.createdAt,
  });

  factory Bus.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Bus(
      id: doc.id,
      busNumber: data['busNumber'] ?? '',
      licensePlate: data['licensePlate'] ?? '',
      status: data['status'] ?? 'Idle',
      currentDriverUid: data['currentDriverUid'],
      currentRoute: data['currentRoute'],
      assignedRouteId: data['assignedRouteId'] as String?,
      capacity: data['capacity'] ?? 40,
      lastLocation: data['lastLocation'] != null
          ? BusLocation.fromMap(data['lastLocation'])
          : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'busNumber': busNumber,
      'licensePlate': licensePlate,
      'status': status,
      'currentDriverUid': currentDriverUid,
      'currentRoute': currentRoute,
      'assignedRouteId': assignedRouteId,
      'capacity': capacity,
      'lastLocation': lastLocation?.toMap(),
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

class BusLocation {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final bool isSimulated;

  BusLocation({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.isSimulated = false,
  });

  factory BusLocation.fromMap(Map<String, dynamic> map) {
    return BusLocation(
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isSimulated: map['isSimulated'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': Timestamp.fromDate(timestamp),
      'isSimulated': isSimulated,
    };
  }
}
