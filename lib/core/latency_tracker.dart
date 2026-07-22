class LatencyTracker {
  static final List<int> _latencySamplesMs = [];

  /// Records a telemetry sync latency sample ($T_{receive} - T_{timestamp}$).
  static void recordSample(DateTime gpsTimestamp) {
    final now = DateTime.now();
    final latencyMs = now.difference(gpsTimestamp).inMilliseconds;
    if (latencyMs >= 0) {
      _latencySamplesMs.add(latencyMs);
      if (_latencySamplesMs.length > 100) {
        _latencySamplesMs.removeAt(0);
      }
    }
  }

  /// Calculates average real-time latency in milliseconds.
  static double get averageLatencyMs {
    if (_latencySamplesMs.isEmpty) return 0.0;
    final total = _latencySamplesMs.reduce((a, b) => a + b);
    return total / _latencySamplesMs.length;
  }

  /// Calculates 95th percentile latency in milliseconds.
  static int get p95LatencyMs {
    if (_latencySamplesMs.isEmpty) return 0;
    final sorted = List<int>.from(_latencySamplesMs)..sort();
    final index = (sorted.length * 0.95).floor();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  /// Reset all recorded samples.
  static void clear() {
    _latencySamplesMs.clear();
  }
}
