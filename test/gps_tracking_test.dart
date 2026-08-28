import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/latency_tracker.dart';
import 'package:schoolway/models/models.dart';

void main() {
  tearDown(LatencyTracker.clear);

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

  test(
    'ten unique updates produce accuracy, continuity, and latency metrics',
    () {
      final startedAt = DateTime.utc(2026, 8, 29, 10);
      for (var index = 0; index < 10; index++) {
        final timestamp = startedAt.add(Duration(seconds: index * 3));
        final tracking = GpsTracking(
          busId: 'bus-a',
          latitude: 3.1 + index * 0.0001,
          longitude: 101.1 + index * 0.0001,
          speed: 20,
          heading: 90,
          accuracy: 4 + index.toDouble(),
          timestamp: timestamp,
          sessionId: 'session-a',
          driverUid: 'driver-a',
        );
        expect(
          LatencyTracker.recordGpsUpdate(
            tracking,
            receivedAt: timestamp.add(Duration(milliseconds: 100 + index * 10)),
          ),
          isTrue,
        );
      }

      final snapshot = LatencyTracker.snapshotForBus('bus-a');
      expect(snapshot.sampleCount, 10);
      expect(snapshot.hasMinimumValidationSamples, isTrue);
      expect(snapshot.averageLatencyMs, 145);
      expect(snapshot.p95LatencyMs, 190);
      expect(snapshot.averageAccuracyMeters, 8.5);
      expect(snapshot.maximumAccuracyMeters, 13);
      expect(snapshot.longestUpdateGap, const Duration(seconds: 3));
    },
  );

  test('repeated and out-of-order snapshots do not inflate samples', () {
    final timestamp = DateTime.utc(2026, 8, 29, 10);
    GpsTracking trackingAt(DateTime time) => GpsTracking(
      busId: 'bus-a',
      latitude: 3.1,
      longitude: 101.1,
      speed: 20,
      heading: 90,
      accuracy: 4,
      timestamp: time,
    );

    expect(
      LatencyTracker.recordGpsUpdate(
        trackingAt(timestamp),
        receivedAt: timestamp.add(const Duration(milliseconds: 100)),
      ),
      isTrue,
    );
    expect(
      LatencyTracker.recordGpsUpdate(
        trackingAt(timestamp),
        receivedAt: timestamp.add(const Duration(milliseconds: 200)),
      ),
      isFalse,
    );
    expect(
      LatencyTracker.recordGpsUpdate(
        trackingAt(timestamp.subtract(const Duration(seconds: 3))),
        receivedAt: timestamp,
      ),
      isFalse,
    );
    expect(LatencyTracker.snapshotForBus('bus-a').sampleCount, 1);
  });
}
