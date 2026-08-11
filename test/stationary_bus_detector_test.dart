import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/stationary_bus_detector.dart';

GpsTracking _gps({required double speed, double latitude = 3.139}) {
  return GpsTracking(
    busId: 'bus-1',
    latitude: latitude,
    longitude: 101.6869,
    speed: speed,
    heading: 0,
    accuracy: 4,
    timestamp: DateTime.now(),
    sessionId: 'session-1',
  );
}

void main() {
  test('warns once, alerts once, and rearms after movement', () async {
    var warnings = 0;
    var alerts = 0;
    final detector = StationaryBusDetector.testing(
      warningThreshold: const Duration(milliseconds: 20),
      alertThreshold: const Duration(milliseconds: 40),
      staleGpsThreshold: const Duration(seconds: 1),
      checkInterval: const Duration(milliseconds: 5),
      alertHandler: (_) async => alerts++,
    );
    detector.start(
      busId: 'bus-1',
      sessionId: 'session-1',
      onWarning: () => warnings++,
    );
    detector.updateGps(_gps(speed: 0));

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(warnings, 1);
    expect(alerts, 1);

    detector.updateGps(_gps(speed: 10));
    detector.updateGps(_gps(speed: 0, latitude: 3.140));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(warnings, 2);
    expect(alerts, 2);
    detector.stop();
  });
}
