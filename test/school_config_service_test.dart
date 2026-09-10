import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/services/school_config_service.dart';

void main() {
  test('geofence controls allow distances up to ten kilometres', () {
    expect(SchoolGeofenceConfig.minimumDistanceMeters, 100);
    expect(SchoolGeofenceConfig.maximumDistanceMeters, 10000);
  });

  test('geofence cache map preserves offline attendance boundaries', () {
    const config = SchoolGeofenceConfig(
      enabled: true,
      latitude: 3.139,
      longitude: 101.6869,
      schoolRadiusMeters: 250,
      routeCorridorMeters: 300,
    );

    final restored = SchoolGeofenceConfig.fromMap(config.toCacheMap());

    expect(restored.enabled, isTrue);
    expect(restored.latitude, config.latitude);
    expect(restored.longitude, config.longitude);
    expect(restored.schoolRadiusMeters, config.schoolRadiusMeters);
    expect(restored.routeCorridorMeters, config.routeCorridorMeters);
  });
}
