import 'package:cloud_firestore/cloud_firestore.dart';

/// In-app / stored notification (Firestore `notifications`).
class InAppNotification {
  final String id;
  final String userId;
  final String title;
  final String body;
  final String type;
  final bool read;
  final DateTime createdAt;
  final String? studentId;
  final String? relatedAlertId;

  InAppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    required this.read,
    required this.createdAt,
    this.studentId,
    this.relatedAlertId,
  });

  factory InAppNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return InAppNotification(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      type: data['type'] as String? ?? 'system',
      read: data['read'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      studentId: data['studentId'] as String?,
      relatedAlertId: data['relatedAlertId'] as String?,
    );
  }
}
