import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:schoolway/core/config.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:latlong2/latlong.dart';

class SchoolGeofenceConfig {
  const SchoolGeofenceConfig({
    required this.enabled,
    required this.latitude,
    required this.longitude,
    required this.schoolRadiusMeters,
    required this.routeCorridorMeters,
  });

  const SchoolGeofenceConfig.disabled()
    : enabled = false,
      latitude = null,
      longitude = null,
      schoolRadiusMeters = 250,
      routeCorridorMeters = 300;

  final bool enabled;
  final double? latitude;
  final double? longitude;
  final double schoolRadiusMeters;
  final double routeCorridorMeters;

  bool get isConfigured => enabled && latitude != null && longitude != null;

  LatLng? get center => isConfigured ? LatLng(latitude!, longitude!) : null;

  factory SchoolGeofenceConfig.fromMap(Map<String, dynamic> data) {
    return SchoolGeofenceConfig(
      enabled: data['geofenceEnabled'] == true,
      latitude: (data['schoolLatitude'] as num?)?.toDouble(),
      longitude: (data['schoolLongitude'] as num?)?.toDouble(),
      schoolRadiusMeters:
          (data['schoolRadiusMeters'] as num?)?.toDouble() ?? 250,
      routeCorridorMeters:
          (data['routeCorridorMeters'] as num?)?.toDouble() ?? 300,
    );
  }

  Map<String, dynamic> toMap() => {
    'geofenceEnabled': enabled,
    'schoolLatitude': latitude,
    'schoolLongitude': longitude,
    'schoolRadiusMeters': schoolRadiusMeters,
    'routeCorridorMeters': routeCorridorMeters,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

class SchoolConfigService {
  static final CollectionReference _configCollection = swFirestore.collection(
    'school_config',
  );

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

  static Future<SchoolGeofenceConfig> getGeofenceConfig() async {
    final doc = await _configCollection.doc('main').get();
    if (!doc.exists) return const SchoolGeofenceConfig.disabled();
    return SchoolGeofenceConfig.fromMap(
      doc.data() as Map<String, dynamic>? ?? const {},
    );
  }

  static Stream<SchoolGeofenceConfig> watchGeofenceConfig() {
    return _configCollection.doc('main').snapshots().map((doc) {
      if (!doc.exists) return const SchoolGeofenceConfig.disabled();
      return SchoolGeofenceConfig.fromMap(
        doc.data() as Map<String, dynamic>? ?? const {},
      );
    });
  }

  static Future<void> saveGeofenceConfig(SchoolGeofenceConfig config) {
    return _configCollection
        .doc('main')
        .set(config.toMap(), SetOptions(merge: true));
  }
}
