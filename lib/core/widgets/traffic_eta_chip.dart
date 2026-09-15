import 'package:flutter/material.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/models/traffic_eta_snapshot.dart';
import 'package:schoolway/services/traffic_eta_service.dart';

enum TrafficEtaDestination { nextStop, school, routeFinish, pickup, dropOff }

/// Compact status chip shown on live maps for the shared server-side Traffic
/// ETA. Shows the next upcoming stop's ETA up to the backend's 5-minute expiry
/// window, then falls back to the localized unavailable label.
class TrafficEtaChip extends StatelessWidget {
  final TrafficEtaState state;
  final TrafficEtaDestination destination;
  final int? Function(TrafficEtaSnapshot snapshot)? etaSelector;
  final int? Function(TrafficEtaSnapshot snapshot)? etaSecondsSelector;

  const TrafficEtaChip({
    super.key,
    required this.state,
    this.destination = TrafficEtaDestination.nextStop,
    this.etaSelector,
    this.etaSecondsSelector,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = context.schoolWayColors;
    final etaSeconds = _etaSeconds(state);
    final etaMinutes = etaSeconds == null ? null : (etaSeconds / 60).ceil();

    final (icon, label, background, foreground) = switch (state.status) {
      TrafficEtaStatus.loading => (
        Icons.sync,
        strings.trafficEtaRefreshing,
        colors.cardBackground,
        theme.colorScheme.primary,
      ),
      TrafficEtaStatus.available when !state.isExpired && etaMinutes != null =>
        (
          Icons.timer,
          _availableLabel(
            strings,
            etaMinutes,
            etaSeconds!,
            countdown: state.countdownAnchor != null,
          ),
          colors.badgeSuccess.withValues(alpha: isDark ? 0.22 : 0.12),
          colors.brandNavy,
        ),
      _ => (
        Icons.timer_off_outlined,
        strings.trafficEtaUnavailable,
        colors.cardBackground,
        colors.mutedText,
      ),
    };

    return Material(
      color: SchoolWayTheme.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: foreground.withValues(alpha: 0.35),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark ? SchoolWayTheme.shadowDark : SchoolWayTheme.text26,
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int? _etaSeconds(TrafficEtaState state) {
    final snapshot = state.snapshot;
    if (snapshot == null) return null;
    final elapsed = state.elapsedCountdownSeconds;
    if (etaSecondsSelector != null) {
      final selectedSeconds = etaSecondsSelector!(snapshot);
      if (selectedSeconds == null) return null;
      return _remainingSeconds(selectedSeconds, elapsed);
    }
    if (etaSelector != null) {
      final selectedMinutes = etaSelector!(snapshot);
      if (selectedMinutes == null) return null;
      return _remainingSeconds(
        selectedMinutes * Duration.secondsPerMinute,
        elapsed,
      );
    }
    if (destination == TrafficEtaDestination.school ||
        destination == TrafficEtaDestination.routeFinish) {
      final durationSeconds = snapshot.durationSeconds;
      if (durationSeconds != null) {
        return _remainingSeconds(durationSeconds, elapsed);
      }
      if (snapshot.stopEtas.isNotEmpty) {
        return _remainingSeconds(
          snapshot.stopEtas.last.etaSeconds ??
              snapshot.stopEtas.last.etaMinutes * Duration.secondsPerMinute,
          elapsed,
        );
      }
      return null;
    }
    if (snapshot.stopEtas.isNotEmpty) {
      return _remainingSeconds(
        snapshot.stopEtas.first.etaSeconds ??
            snapshot.stopEtas.first.etaMinutes * Duration.secondsPerMinute,
        elapsed,
      );
    }
    final durationSeconds = snapshot.durationSeconds;
    return durationSeconds == null
        ? null
        : _remainingSeconds(durationSeconds, elapsed);
  }

  int _remainingSeconds(int seconds, int elapsed) =>
      (seconds - elapsed).clamp(0, 86400);

  String _availableLabel(
    AppLocalizations strings,
    int minutes,
    int seconds, {
    required bool countdown,
  }) {
    if (countdown) {
      final countdownMinutes = seconds ~/ Duration.secondsPerMinute;
      final countdownSeconds = seconds % Duration.secondsPerMinute;
      return switch (destination) {
        TrafficEtaDestination.school => strings.etaToSchoolCountdown(
          countdownMinutes,
          countdownSeconds,
        ),
        TrafficEtaDestination.routeFinish => strings.etaToRouteFinishCountdown(
          countdownMinutes,
          countdownSeconds,
        ),
        TrafficEtaDestination.pickup => strings.etaToPickupPointCountdown(
          countdownMinutes,
          countdownSeconds,
        ),
        TrafficEtaDestination.dropOff => strings.etaToDropOffPointCountdown(
          countdownMinutes,
          countdownSeconds,
        ),
        TrafficEtaDestination.nextStop => strings.trafficEtaCountdownLabel(
          countdownMinutes,
          countdownSeconds,
        ),
      };
    }
    if (seconds < Duration.secondsPerMinute) {
      return switch (destination) {
        TrafficEtaDestination.school => strings.etaToSchoolSeconds(seconds),
        TrafficEtaDestination.routeFinish => strings.etaToRouteFinishSeconds(
          seconds,
        ),
        TrafficEtaDestination.pickup => strings.etaToPickupPointSeconds(
          seconds,
        ),
        TrafficEtaDestination.dropOff => strings.etaToDropOffPointSeconds(
          seconds,
        ),
        TrafficEtaDestination.nextStop => strings.trafficEtaSecondsLabel(
          seconds,
        ),
      };
    }
    return switch (destination) {
      TrafficEtaDestination.school => strings.etaToSchool(minutes),
      TrafficEtaDestination.routeFinish => strings.etaToRouteFinish(minutes),
      TrafficEtaDestination.pickup => strings.etaToPickupPoint(minutes),
      TrafficEtaDestination.dropOff => strings.etaToDropOffPoint(minutes),
      TrafficEtaDestination.nextStop => strings.trafficEtaMinutesLabel(minutes),
    };
  }
}
