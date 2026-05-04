import 'package:cloud_firestore/cloud_firestore.dart';

class Student {
  final String id;
  final String studentId;
  final String firstName;
  final String lastName;
  final String nfcCardId;
  final List<String> parentIds;
  final String? assignedBusId;
  final String? assignedRouteId;
  final String? pickupStop;
  final String? dropoffStop;
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
    required this.parentIds,
    this.assignedBusId,
    this.assignedRouteId,
    this.pickupStop,
    this.dropoffStop,
    required this.status,
    this.classId,
    required this.createdAt,
  });

  String get fullName => '$firstName $lastName';

  factory Student.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Student(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      nfcCardId: data['nfcCardId'] ?? '',
      parentIds: List<String>.from(data['parentIds'] ?? []),
      assignedBusId: data['assignedBusId'],
      assignedRouteId: data['assignedRouteId'],
      pickupStop: data['pickupStop'],
      dropoffStop: data['dropoffStop'],
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
      'parentIds': parentIds,
      'assignedBusId': assignedBusId,
      'assignedRouteId': assignedRouteId,
      'pickupStop': pickupStop,
      'dropoffStop': dropoffStop,
      'status': status,
      'classId': classId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

