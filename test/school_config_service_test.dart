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

  test('schoolLocation returns LatLng even when geofencing is disabled', () {
    const config = SchoolGeofenceConfig(
      enabled: false,
      latitude: 4.332,
      longitude: 101.141,
      schoolRadiusMeters: 250,
      routeCorridorMeters: 300,
    );

    expect(config.isConfigured, isFalse);
    expect(config.center, isNull);
    expect(config.schoolLocation, isNotNull);
    expect(config.schoolLocation!.latitude, 4.332);
    expect(config.schoolLocation!.longitude, 101.141);
  });

  test('schoolLocation returns null when coordinates are not configured', () {
    const config = SchoolGeofenceConfig.disabled();

    expect(config.schoolLocation, isNull);
  });

  test('route planner uses the authoritative UTAR school endpoint', () async {
    final location = await SchoolConfigService.getRoutePlannerSchoolLocation();

    expect(location.latitude, 4.33834);
    expect(location.longitude, 101.13578);
  });
}
