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

  const TrafficEtaChip({
    super.key,
    required this.state,
    this.destination = TrafficEtaDestination.nextStop,
    this.etaSelector,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = context.schoolWayColors;
    final etaMinutes = _etaMinutes(state);

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
          _availableLabel(strings, etaMinutes),
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

  int? _etaMinutes(TrafficEtaState state) {
    final snapshot = state.snapshot;
    if (snapshot == null) return null;
    if (etaSelector != null) return etaSelector!(snapshot);
    if (destination == TrafficEtaDestination.school ||
        destination == TrafficEtaDestination.routeFinish) {
      final durationSeconds = snapshot.durationSeconds;
      if (durationSeconds != null) {
        return (durationSeconds / Duration.secondsPerMinute).ceil();
      }
      if (snapshot.stopEtas.isNotEmpty) {
        return snapshot.stopEtas.last.etaMinutes;
      }
      return null;
    }
    if (snapshot.stopEtas.isNotEmpty) {
      return snapshot.stopEtas.first.etaMinutes;
    }
    final durationSeconds = snapshot.durationSeconds;
    if (durationSeconds == null) return null;
    return (durationSeconds / Duration.secondsPerMinute).ceil();
  }

  String _availableLabel(AppLocalizations strings, int minutes) {
    return switch (destination) {
      TrafficEtaDestination.school => strings.etaToSchool(minutes),
      TrafficEtaDestination.routeFinish => strings.etaToRouteFinish(minutes),
      TrafficEtaDestination.pickup => strings.etaToPickupPoint(minutes),
      TrafficEtaDestination.dropOff => strings.etaToDropOffPoint(minutes),
      TrafficEtaDestination.nextStop => strings.trafficEtaMinutesLabel(minutes),
    };
  }
}
