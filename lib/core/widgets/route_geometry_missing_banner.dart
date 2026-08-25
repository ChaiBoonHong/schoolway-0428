import 'package:flutter/material.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/l10n/app_localizations.dart';

/// Inline notice shown when a route has stops but no usable Google geometry,
/// so the missing route line is never a silent degradation.
class RouteGeometryMissingBanner extends StatelessWidget {
  const RouteGeometryMissingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Material(
      color: SchoolWayTheme.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: SchoolWayTheme.warning,
              semanticLabel: strings.routeGeometryUnavailableBanner,
            ),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                strings.routeGeometryUnavailableBanner,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: SchoolWayTheme.navy,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
