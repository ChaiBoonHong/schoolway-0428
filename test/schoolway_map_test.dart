import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/map/schoolway_map.dart';

void main() {
  test('map gesture priority is opt-in for embedded editors', () {
    const defaultMap = SchoolWayMap(initialCenter: LatLng(3.1, 101.7));
    const editorMap = SchoolWayMap(
      initialCenter: LatLng(3.1, 101.7),
      eagerGestureHandling: true,
    );

    expect(defaultMap.eagerGestureHandling, isFalse);
    expect(editorMap.eagerGestureHandling, isTrue);
  });

  test('geofence circles retain a transparent fill and visible outline', () {
    const circle = SchoolWayMapCircle(
      id: 'school-geofence',
      latitude: 3.1,
      longitude: 101.7,
      radiusMeters: 250,
      fillColor: Color(0x00000000),
      strokeColor: Color(0xFF0067B1),
    );
    const map = SchoolWayMap(
      initialCenter: LatLng(3.1, 101.7),
      circles: [circle],
    );

    expect(map.circles, hasLength(1));
    expect(map.circles.single.fillColor.a, 0);
    expect(map.circles.single.strokeColor.a, 1);
  });
}
