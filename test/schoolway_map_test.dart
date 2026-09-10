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
}
