import 'package:cloud_firestore/cloud_firestore.dart';

class Student {
  final String id;
  final String studentId;
  final String firstName;
  final String lastName;
  final String nfcCardId;
  final List<String> parentAuthUids;
  final String? assignedBusId;
  final String? assignedRouteId;
  final String? pickupStop;
  final String? dropoffStop;
  final int? pickupStopIndex;
  final int? dropoffStopIndex;
  final String status; // 'Active', 'Inactive'
  /// Kindergarten class (e.g. K1, K2, K3). K1 = age 4, K2 = age 5, K3 = age 6.
  final String? classId;
  final DateTime createdAt;

  Student({
    required this.id,
    required this.studentId,
    required this.firstName,
    required this.lastName,
    required this.nfcCardId,
    required this.parentAuthUids,
    this.assignedBusId,
    this.assignedRouteId,
    this.pickupStop,
    this.dropoffStop,
    this.pickupStopIndex,
    this.dropoffStopIndex,
    required this.status,
    this.classId,
    required this.createdAt,
  });

  String get fullName => '$firstName $lastName';

  String get assignedStopName {
    if (pickupStop != null && pickupStop!.isNotEmpty) return pickupStop!;
    if (dropoffStop != null && dropoffStop!.isNotEmpty) return dropoffStop!;
    return 'Unassigned Stop';
  }

  factory Student.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Student(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      nfcCardId: data['nfcCardId'] ?? '',
      parentAuthUids: List<String>.from(data['parentAuthUids'] ?? []),
      assignedBusId: data['assignedBusId'],
      assignedRouteId: data['assignedRouteId'],
      pickupStop: data['pickupStop'],
      dropoffStop: data['dropoffStop'],
      pickupStopIndex: (data['pickupStopIndex'] as num?)?.toInt(),
      dropoffStopIndex: (data['dropoffStopIndex'] as num?)?.toInt(),
      status: data['status'] ?? 'Active',
      classId: data['classId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'studentId': studentId,
      'firstName': firstName,
      'lastName': lastName,
      'nfcCardId': nfcCardId,
      'parentAuthUids': parentAuthUids,
      'assignedBusId': assignedBusId,
      'assignedRouteId': assignedRouteId,
      'pickupStop': pickupStop,
      'dropoffStop': dropoffStop,
      'pickupStopIndex': pickupStopIndex,
      'dropoffStopIndex': dropoffStopIndex,
      'status': status,
      'classId': classId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
