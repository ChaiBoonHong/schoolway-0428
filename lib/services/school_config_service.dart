import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:schoolway/core/config.dart';
import 'package:schoolway/core/schoolway_firestore.dart';

class SchoolConfigService {
  static final CollectionReference _configCollection = swFirestore.collection('school_config');

  /// Fetches the admin phone number from Firestore or falls back to AppConfig.
  static Future<String> getAdminPhoneNumber() async {
    try {
      final doc = await _configCollection.doc('main').get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final phone = data['adminPhoneNumber'] as String?;
        if (phone != null && phone.isNotEmpty) {
          return phone;
        }
      }
    } catch (_) {
      // Fallback
    }
    return AppConfig.adminPhoneNumber;
  }
}
