import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/models/gps_tracking.dart';
import 'package:schoolway/services/emergency_alert_location.dart';

void main() {
  GpsTracking tracking({
    bool simulated = false,
    String sessionId = 'session',
    String driverUid = 'driver',
    DateTime? timestamp,
  }) => GpsTracking(
    busId: 'bus',
    latitude: 3.14159,
    longitude: 101.68653,
    speed: 0,
    heading: 0,
    accuracy: 5,
    timestamp: timestamp ?? DateTime(2026, 1, 1, 8),
    sessionId: sessionId,
    driverUid: driverUid,
    isSimulated: simulated,
  );

  test('uses the current simulated bus fix for the active session', () {
    final simulated = tracking(simulated: true);
    expect(
      emergencyLocationForActiveSession(
        tracking: simulated,
        sessionId: 'session',
        driverUid: 'driver',
        now: DateTime(2026, 1, 1, 8, 1),
      ),
      same(simulated),
    );
  });

  test('rejects stale and mismatched tracking fixes', () {
    final now = DateTime(2026, 1, 1, 8, 2);
    expect(
      emergencyLocationForActiveSession(
        tracking: tracking(timestamp: DateTime(2026, 1, 1, 8)),
        sessionId: 'session',
        driverUid: 'driver',
        now: now,
      ),
      isNull,
    );
    expect(
      emergencyLocationForActiveSession(
        tracking: tracking(sessionId: 'other-session'),
        sessionId: 'session',
        driverUid: 'driver',
        now: DateTime(2026, 1, 1, 8, 1),
      ),
      isNull,
    );
  });
}
