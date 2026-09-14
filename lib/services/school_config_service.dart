import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:schoolway/core/config.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SchoolGeofenceConfig {
  static const double minimumDistanceMeters = 100;
  static const double maximumDistanceMeters = 10000;

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

  /// The stored school location is useful to route planning even when the
  /// optional geofence feature is disabled.
  LatLng? get schoolLocation => latitude != null && longitude != null
      ? LatLng(latitude!, longitude!)
      : null;

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

  Map<String, dynamic> toCacheMap() => {
    'geofenceEnabled': enabled,
    'schoolLatitude': latitude,
    'schoolLongitude': longitude,
    'schoolRadiusMeters': schoolRadiusMeters,
    'routeCorridorMeters': routeCorridorMeters,
  };
}

class SchoolConfigService {
  static const LatLng defaultRouteSchoolLocation = LatLng(
    4.33834,
    101.13578,
  );
  static const String _cacheBoxName = 'school_config_cache';
  static const String _geofenceCacheKey = 'geofence';
  static SchoolGeofenceConfig? _memoryGeofenceConfig;
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
    try {
      final doc = await _configCollection.doc('main').get();
      final config = doc.exists
          ? SchoolGeofenceConfig.fromMap(
              doc.data() as Map<String, dynamic>? ?? const {},
            )
          : const SchoolGeofenceConfig.disabled();
      _memoryGeofenceConfig = config;
      await _writeCachedGeofenceConfig(config);
      return config;
    } catch (_) {
      final cached = _memoryGeofenceConfig ?? await _readCachedGeofenceConfig();
      if (cached != null) return cached;
      rethrow;
    }
  }

  static Future<LatLng> getRoutePlannerSchoolLocation() async =>
      defaultRouteSchoolLocation;

  static Stream<SchoolGeofenceConfig> watchGeofenceConfig() {
    return _configCollection.doc('main').snapshots().asyncMap((doc) async {
      final config = !doc.exists
          ? const SchoolGeofenceConfig.disabled()
          : SchoolGeofenceConfig.fromMap(
              doc.data() as Map<String, dynamic>? ?? const {},
            );
      _memoryGeofenceConfig = config;
      await _writeCachedGeofenceConfig(config);
      return config;
    });
  }

  static Future<Box<dynamic>> _cacheBox() async {
    if (Hive.isBoxOpen(_cacheBoxName)) return Hive.box(_cacheBoxName);
    return Hive.openBox<dynamic>(_cacheBoxName);
  }

  static Future<void> _writeCachedGeofenceConfig(
    SchoolGeofenceConfig config,
  ) async {
    final box = await _cacheBox();
    await box.put(_geofenceCacheKey, config.toCacheMap());
  }

  static Future<SchoolGeofenceConfig?> _readCachedGeofenceConfig() async {
    final box = await _cacheBox();
    final raw = box.get(_geofenceCacheKey);
    if (raw is! Map) return null;
    final config = SchoolGeofenceConfig.fromMap(Map<String, dynamic>.from(raw));
    _memoryGeofenceConfig = config;
    return config;
  }

  static Future<void> saveGeofenceConfig(SchoolGeofenceConfig config) {
    return _configCollection
        .doc('main')
        .set(config.toMap(), SetOptions(merge: true));
  }
}
