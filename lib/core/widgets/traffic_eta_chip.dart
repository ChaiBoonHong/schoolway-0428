import 'package:flutter/material.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/services/traffic_eta_service.dart';

/// Compact status chip shown on live maps for the shared server-side Traffic
/// ETA. Shows “updated … ago” up to the backend's 5-minute expiry window, then
/// falls back to the localized unavailable label.
class TrafficEtaChip extends StatelessWidget {
  final TrafficEtaState state;

  const TrafficEtaChip({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = context.schoolWayColors;

    final (icon, label, background, foreground) = switch (state.status) {
      TrafficEtaStatus.loading => (
        Icons.sync,
        strings.trafficEtaRefreshing,
        colors.cardBackground,
        theme.colorScheme.primary,
      ),
      TrafficEtaStatus.available when !state.isExpired => (
        Icons.timer,
        _updatedLabel(strings, state),
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

  String _updatedLabel(AppLocalizations strings, TrafficEtaState state) {
    final age = state.snapshot?.age;
    if (age == null) return strings.trafficEtaUpdatedLabel;
    final minutes = age.inMinutes;
    final ago = minutes < 1
        ? 'just now'
        : minutes < 60
        ? '$minutes min ago'
        : '${age.inHours} hr ago';
    return '${strings.trafficEtaUpdatedLabel} · $ago';
  }
}
