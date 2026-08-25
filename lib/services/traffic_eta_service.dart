import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/routes_api_service.dart';

enum TrafficEtaStatus { idle, loading, available, unavailable }

class TrafficEtaState {
  final TrafficEtaStatus status;
  final TrafficEtaSnapshot? snapshot;

  /// When the last server response was received.
  final DateTime? lastUpdated;
  final Object? error;

  const TrafficEtaState({
    this.status = TrafficEtaStatus.idle,
    this.snapshot,
    this.lastUpdated,
    this.error,
  });

  bool get isAvailable => status == TrafficEtaStatus.available;

  bool get isExpired => snapshot?.isExpired ?? false;
}

/// Refreshes the shared server-side Traffic ETA for one active session.
///
/// The backend enforces a 60-second freshness window and deduplicates
/// simultaneous requests with a transactional lease, so the client only needs
/// to poll on that cadence (plus an immediate refresh when the session or
/// progress changes).
class TrafficEtaService {
  static const Duration _refreshInterval = Duration(seconds: 60);

  /// Injectable fetch for tests; defaults to the backend callable.
  final Future<TrafficEtaSnapshot> Function(String sessionId) _fetch;

  final ValueNotifier<TrafficEtaState> state = ValueNotifier(
    const TrafficEtaState(),
  );

  Timer? _timer;
  String? _sessionId;
  int _generation = 0;

  TrafficEtaService({
    Future<TrafficEtaSnapshot> Function(String sessionId)? fetch,
  }) : _fetch = fetch ?? RoutesApiService.getTrafficEta;

  /// Starts polling for [sessionId]. Stops any previous session.
  void start(String sessionId) {
    if (sessionId == _sessionId && _timer != null) return;
    stop();
    _sessionId = sessionId;
    unawaited(refresh());
    _timer = Timer.periodic(_refreshInterval, (_) {
      unawaited(refresh());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _sessionId = null;
    _generation++;
    state.value = const TrafficEtaState();
  }

  Future<void> refresh() async {
    final sessionId = _sessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    final gen = ++_generation;
    state.value = const TrafficEtaState(status: TrafficEtaStatus.loading);
    try {
      final snapshot = await _fetch(sessionId);
      if (gen != _generation) return;
      final available = snapshot.isOk && !snapshot.isExpired;
      state.value = TrafficEtaState(
        status: available
            ? TrafficEtaStatus.available
            : TrafficEtaStatus.unavailable,
        snapshot: snapshot,
        lastUpdated: DateTime.now(),
      );
    } catch (error) {
      if (gen != _generation) return;
      state.value = TrafficEtaState(
        status: TrafficEtaStatus.unavailable,
        lastUpdated: DateTime.now(),
        error: error,
      );
    }
  }

  void dispose() {
    stop();
    state.dispose();
  }
}
