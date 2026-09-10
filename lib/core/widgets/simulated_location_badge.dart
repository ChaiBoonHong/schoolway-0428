import 'package:flutter/material.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/l10n/app_localizations.dart';

class SimulatedLocationBadge extends StatelessWidget {
  const SimulatedLocationBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).simulationActive;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark
        ? SchoolWayTheme.warning
        : SchoolWayTheme.warningDark;

    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('simulated-location-badge'),
          padding: const EdgeInsets.symmetric(
            horizontal: SchoolWayTheme.spacing12,
            vertical: SchoolWayTheme.spacing8,
          ),
          decoration: BoxDecoration(
            color: SchoolWayTheme.warning.withValues(
              alpha: isDark ? 0.2 : 0.14,
            ),
            borderRadius: BorderRadius.circular(SchoolWayTheme.radius),
            border: Border.all(color: foreground),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.science_outlined, size: 18, color: foreground),
              const SizedBox(width: SchoolWayTheme.spacing8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
