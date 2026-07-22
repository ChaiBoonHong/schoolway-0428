import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents an audited correction to a student's attendance record.
class AttendanceCorrection {
  final String id;
  final String originalEventId;
  final String studentId;
  final String correctedBy; // User ID / Email of admin or driver
  final String oldEventType;
  final String newEventType;
  final String reason;
  final DateTime timestamp;

  AttendanceCorrection({
    required this.id,
    required this.originalEventId,
    required this.studentId,
    required this.correctedBy,
    required this.oldEventType,
    required this.newEventType,
    required this.reason,
    required this.timestamp,
  });

  factory AttendanceCorrection.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AttendanceCorrection(
      id: doc.id,
      originalEventId: data['originalEventId'] ?? '',
      studentId: data['studentId'] ?? '',
      correctedBy: data['correctedBy'] ?? '',
      oldEventType: data['oldEventType'] ?? '',
      newEventType: data['newEventType'] ?? '',
      reason: data['reason'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'originalEventId': originalEventId,
      'studentId': studentId,
      'correctedBy': correctedBy,
      'oldEventType': oldEventType,
      'newEventType': newEventType,
      'reason': reason,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
