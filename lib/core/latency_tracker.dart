import '../models/gps_tracking.dart';

/// Measures unique GPS updates received by a Parent or Admin device.
class LatencyTracker {
  static const int requiredValidationSamples = 10;
  static const int _maxSamplesPerBus = 100;

  static final Map<String, List<GpsTelemetrySample>> _samplesByBus = {};
  static final Map<String, DateTime> _lastTimestampByBus = {};

  /// Records one driver-to-viewer update. Rebuilt widgets and repeated or
  /// out-of-order Firestore snapshots are ignored so they cannot inflate a
  /// physical validation run.
  static bool recordGpsUpdate(GpsTracking gps, {DateTime? receivedAt}) {
    final received = receivedAt ?? DateTime.now();
    final previousTimestamp = _lastTimestampByBus[gps.busId];
    if (previousTimestamp != null &&
        !gps.timestamp.isAfter(previousTimestamp)) {
      return false;
    }

    final latencyMs = received.difference(gps.timestamp).inMilliseconds;
    if (latencyMs < 0) return false;

    final samples = _samplesByBus.putIfAbsent(gps.busId, () => []);
    samples.add(
      GpsTelemetrySample(
        sourceTimestamp: gps.timestamp,
        receivedAt: received,
        latencyMs: latencyMs,
        accuracyMeters: gps.accuracy,
      ),
    );
    if (samples.length > _maxSamplesPerBus) samples.removeAt(0);
    _lastTimestampByBus[gps.busId] = gps.timestamp;
    return true;
  }

  /// Compatibility helper for timestamp-only instrumentation.
  static void recordSample(DateTime gpsTimestamp) {
    recordGpsUpdate(
      GpsTracking(
        busId: '_legacy',
        latitude: 0,
        longitude: 0,
        speed: 0,
        heading: 0,
        accuracy: 0,
        timestamp: gpsTimestamp,
      ),
    );
  }

  static GpsValidationSnapshot snapshotForBus(String busId) =>
      GpsValidationSnapshot.fromSamples(_samplesByBus[busId] ?? const []);

  static List<GpsTelemetrySample> get _allSamples =>
      _samplesByBus.values.expand((samples) => samples).toList();

  static double get averageLatencyMs =>
      GpsValidationSnapshot.fromSamples(_allSamples).averageLatencyMs;

  static int get p95LatencyMs =>
      GpsValidationSnapshot.fromSamples(_allSamples).p95LatencyMs;

  static void clear() {
    _samplesByBus.clear();
    _lastTimestampByBus.clear();
  }
}

class GpsTelemetrySample {
  const GpsTelemetrySample({
    required this.sourceTimestamp,
    required this.receivedAt,
    required this.latencyMs,
    required this.accuracyMeters,
  });

  final DateTime sourceTimestamp;
  final DateTime receivedAt;
  final int latencyMs;
  final double accuracyMeters;
}

class GpsValidationSnapshot {
  const GpsValidationSnapshot({
    required this.sampleCount,
    required this.averageLatencyMs,
    required this.p95LatencyMs,
    required this.averageAccuracyMeters,
    required this.maximumAccuracyMeters,
    required this.longestUpdateGap,
  });

  factory GpsValidationSnapshot.fromSamples(List<GpsTelemetrySample> samples) {
    if (samples.isEmpty) {
      return const GpsValidationSnapshot(
        sampleCount: 0,
        averageLatencyMs: 0,
        p95LatencyMs: 0,
        averageAccuracyMeters: 0,
        maximumAccuracyMeters: 0,
        longestUpdateGap: Duration.zero,
      );
    }

    final latencyValues = samples.map((sample) => sample.latencyMs).toList()
      ..sort();
    final accuracyValues = samples
        .map((sample) => sample.accuracyMeters)
        .where((accuracy) => accuracy.isFinite && accuracy >= 0)
        .toList();
    var longestGap = Duration.zero;
    for (var index = 1; index < samples.length; index++) {
      final gap = samples[index].sourceTimestamp.difference(
        samples[index - 1].sourceTimestamp,
      );
      if (gap > longestGap) longestGap = gap;
    }
    final p95Index = ((latencyValues.length * 0.95).ceil() - 1).clamp(
      0,
      latencyValues.length - 1,
    );

    return GpsValidationSnapshot(
      sampleCount: samples.length,
      averageLatencyMs:
          latencyValues.reduce((left, right) => left + right) /
          latencyValues.length,
      p95LatencyMs: latencyValues[p95Index],
      averageAccuracyMeters: accuracyValues.isEmpty
          ? 0
          : accuracyValues.reduce((left, right) => left + right) /
                accuracyValues.length,
      maximumAccuracyMeters: accuracyValues.isEmpty
          ? 0
          : accuracyValues.reduce((left, right) => left > right ? left : right),
      longestUpdateGap: longestGap,
    );
  }

  final int sampleCount;
  final double averageLatencyMs;
  final int p95LatencyMs;
  final double averageAccuracyMeters;
  final double maximumAccuracyMeters;
  final Duration longestUpdateGap;

  bool get hasMinimumValidationSamples =>
      sampleCount >= LatencyTracker.requiredValidationSamples;
}
