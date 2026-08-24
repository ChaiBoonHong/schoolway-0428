import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/models/models.dart';

void main() {
  test('GPS writes include the authenticated driver UID', () {
    final tracking = GpsTracking(
      busId: 'bus-a',
      latitude: 3.1,
      longitude: 101.1,
      speed: 20,
      heading: 90,
      accuracy: 4,
      timestamp: DateTime.utc(2026),
      sessionId: 'session-a',
      driverUid: 'driver-a',
    );

    expect(tracking.toFirestore()['driverUid'], 'driver-a');
  });
}
