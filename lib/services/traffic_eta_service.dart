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

  /// Forces map chips to rebuild while the displayed ETA counts down.
  final int countdownTick;

  /// When the current server snapshot became the active displayed estimate.
  final DateTime? countdownAnchor;

  const TrafficEtaState({
    this.status = TrafficEtaStatus.idle,
    this.snapshot,
    this.lastUpdated,
    this.error,
    this.countdownTick = 0,
    this.countdownAnchor,
  });

  bool get isAvailable => status == TrafficEtaStatus.available;

  bool get isExpired => snapshot?.isExpired ?? false;

  int get elapsedCountdownSeconds {
    final anchor = countdownAnchor;
    if (anchor == null) return 0;
    return DateTime.now().difference(anchor).inSeconds.clamp(0, 86400);
  }
}

/// Refreshes the shared server-side Traffic ETA for one active session.
///
/// The backend enforces a short shared freshness window and deduplicates
/// simultaneous requests with a transactional lease, so the client only needs
/// to poll on that cadence (plus an immediate refresh when the session or
/// progress changes).
class TrafficEtaService {
  static const Duration _refreshInterval = Duration(seconds: 2);
  static const Duration _countdownInterval = Duration(seconds: 1);

  /// Injectable fetch for tests; defaults to the backend callable.
  final Future<TrafficEtaSnapshot> Function(String sessionId) _fetch;

  final ValueNotifier<TrafficEtaState> state = ValueNotifier(
    const TrafficEtaState(),
  );

  Timer? _refreshTimer;
  Timer? _countdownTimer;
  String? _sessionId;
  int _generation = 0;
  bool _refreshInProgress = false;

  TrafficEtaService({
    Future<TrafficEtaSnapshot> Function(String sessionId)? fetch,
  }) : _fetch = fetch ?? RoutesApiService.getTrafficEta;

  /// Starts polling for [sessionId]. Stops any previous session.
  void start(String sessionId) {
    if (sessionId == _sessionId && _refreshTimer != null) return;
    stop();
    _sessionId = sessionId;
    unawaited(refresh());
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      unawaited(refresh());
    });
    _countdownTimer = Timer.periodic(_countdownInterval, (_) {
      _publishCountdownTick();
    });
  }

  void stop() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _sessionId = null;
    _generation++;
    state.value = const TrafficEtaState();
  }

  Future<void> refresh() async {
    final sessionId = _sessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    if (_refreshInProgress) return;
    _refreshInProgress = true;
    final gen = ++_generation;
    final previous = state.value;
    // Do not replace a usable ETA with a loading state on each polling cycle.
    // It makes the chip and traffic polyline visibly blink while a fresh value
    // is being requested. Loading is only meaningful before the first result.
    if (previous.snapshot == null) {
      state.value = TrafficEtaState(
        status: TrafficEtaStatus.loading,
        lastUpdated: previous.lastUpdated,
        countdownTick: previous.countdownTick,
        countdownAnchor: previous.countdownAnchor,
      );
    }
    try {
      final snapshot = await _fetch(sessionId);
      if (gen != _generation) return;
      final available = snapshot.isOk && !snapshot.isExpired;
      final terminalArrived =
          snapshot.reason == TrafficEtaReason.allStopsCompleted;
      // Preserve a live ETA during transient unavailability, but never hide
      // the terminal result behind the previous near-zero countdown.
      final keepPrevious =
          !terminalArrived &&
          !available &&
          previous.snapshot != null &&
          previous.snapshot!.isAvailable;
      final displayedSnapshot = keepPrevious ? previous.snapshot! : snapshot;
      final hasNewSnapshot = _snapshotChanged(previous.snapshot, snapshot);
      state.value = TrafficEtaState(
        status: available || keepPrevious
            ? TrafficEtaStatus.available
            : TrafficEtaStatus.unavailable,
        snapshot: displayedSnapshot,
        lastUpdated: DateTime.now(),
        countdownTick: previous.countdownTick,
        countdownAnchor: hasNewSnapshot
            ? DateTime.now()
            : previous.countdownAnchor,
      );
    } catch (error) {
      if (gen != _generation) return;
      final keepPrevious = previous.snapshot?.isAvailable ?? false;
      state.value = TrafficEtaState(
        status: keepPrevious
            ? TrafficEtaStatus.available
            : TrafficEtaStatus.unavailable,
        snapshot: keepPrevious ? previous.snapshot : null,
        lastUpdated: DateTime.now(),
        error: error,
        countdownTick: previous.countdownTick,
        countdownAnchor: previous.countdownAnchor,
      );
    } finally {
      _refreshInProgress = false;
    }
  }

  void _publishCountdownTick() {
    final current = state.value;
    if (current.snapshot == null || !current.isAvailable) return;
    state.value = TrafficEtaState(
      status: current.status,
      snapshot: current.snapshot,
      lastUpdated: current.lastUpdated,
      error: current.error,
      countdownTick: current.countdownTick + 1,
      countdownAnchor: current.countdownAnchor,
    );
  }

  bool _snapshotChanged(TrafficEtaSnapshot? previous, TrafficEtaSnapshot next) {
    if (previous == null ||
        previous.generatedAt != next.generatedAt ||
        previous.sourceGpsTime != next.sourceGpsTime ||
        previous.durationSeconds != next.durationSeconds ||
        previous.stopEtas.length != next.stopEtas.length) {
      return true;
    }
    for (var i = 0; i < next.stopEtas.length; i++) {
      final oldEta = previous.stopEtas[i];
      final newEta = next.stopEtas[i];
      if (oldEta.routeStopIndex != newEta.routeStopIndex ||
          oldEta.etaSeconds != newEta.etaSeconds ||
          oldEta.etaMinutes != newEta.etaMinutes) {
        return true;
      }
    }
    return false;
  }

  void dispose() {
    stop();
    state.dispose();
  }
}
