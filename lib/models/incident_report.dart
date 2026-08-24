import 'package:cloud_firestore/cloud_firestore.dart';

/// In-app incident report logged by drivers or staff.
class IncidentReport {
  final String id;
  final String driverUid;
  final String busId;
  final String? sessionId;
  final String
  category; // 'Late Arrival', 'Route Disruption', 'Student Absence', 'Vehicle Issue', 'Other'
  final String description;
  final String severity; // 'Low', 'Medium', 'High', 'Critical'
  final DateTime timestamp;
  final bool resolved;

  IncidentReport({
    required this.id,
    required this.driverUid,
    required this.busId,
    this.sessionId,
    required this.category,
    required this.description,
    this.severity = 'Medium',
    required this.timestamp,
    this.resolved = false,
  });

  factory IncidentReport.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return IncidentReport(
      id: doc.id,
      driverUid: data['driverUid'] as String? ?? '',
      busId: data['busId'] as String? ?? '',
      sessionId: data['sessionId'] as String?,
      category: data['category'] as String? ?? 'General',
      description: data['description'] as String? ?? '',
      severity: data['severity'] as String? ?? 'Medium',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      resolved: data['resolved'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'driverUid': driverUid,
      'busId': busId,
      'sessionId': sessionId,
      'category': category,
      'description': description,
      'severity': severity,
      'timestamp': Timestamp.fromDate(timestamp),
      'resolved': resolved,
    };
  }
}
