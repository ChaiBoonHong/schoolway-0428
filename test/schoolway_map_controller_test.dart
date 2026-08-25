import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/map/schoolway_map_controller.dart';

void main() {
  test('move before attach buffers the request', () async {
    final controller = SchoolWayMapController();
    addTearDown(controller.dispose);

    await controller.move(center: const LatLng(3.1, 101.7), zoom: 14);
    expect(controller.lastRequestedCenter, const LatLng(3.1, 101.7));
  });

  test('fitBounds buffers a computed center before attach', () async {
    final controller = SchoolWayMapController();
    addTearDown(controller.dispose);

    await controller.fitBounds(
      southLatitude: 3.0,
      westLongitude: 101.5,
      northLatitude: 3.2,
      eastLongitude: 101.9,
    );
    expect(controller.lastRequestedCenter, isNotNull);
    expect(controller.lastRequestedCenter!.latitude, closeTo(3.1, 1e-9));
  });

  test('dispose stops future moves without throwing', () async {
    final controller = SchoolWayMapController();
    controller.dispose();

    await controller.move(center: const LatLng(3.1, 101.7), zoom: 14);
    await controller.fitBounds(
      southLatitude: 3.0,
      westLongitude: 101.5,
      northLatitude: 3.2,
      eastLongitude: 101.9,
    );
    expect(controller.lastRequestedCenter, isNull);
  });
}
