import 'package:flutter/material.dart';

import '../../../core/theme/schoolway_theme.dart';
import '../../../l10n/app_localizations.dart';

class CsvPreviewSummary extends StatelessWidget {
  const CsvPreviewSummary({
    required this.totalRows,
    required this.validRows,
    required this.invalidRows,
    required this.duplicateRows,
    required this.existingRows,
    super.key,
  });

  final int totalRows;
  final int validRows;
  final int invalidRows;
  final int duplicateRows;
  final int existingRows;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statuses = <_CsvPreviewStatus>[
      _CsvPreviewStatus(
        label: localizations.valid,
        value: validRows,
        icon: Icons.check_circle_outline,
        color: isDark
            ? SchoolWayTheme.successBright
            : SchoolWayTheme.successDark,
      ),
      _CsvPreviewStatus(
        label: localizations.invalid,
        value: invalidRows,
        icon: Icons.cancel_outlined,
        color: theme.colorScheme.error,
      ),
      _CsvPreviewStatus(
        label: localizations.duplicates,
        value: duplicateRows,
        icon: Icons.warning_amber_outlined,
        color: isDark ? SchoolWayTheme.warning : SchoolWayTheme.warningDark,
      ),
      _CsvPreviewStatus(
        label: localizations.existingInDatabase,
        value: existingRows,
        icon: Icons.storage_outlined,
        color: isDark ? SchoolWayTheme.violet : SchoolWayTheme.purple,
      ),
    ];

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            label: localizations.csvRecordsTotal(totalRows),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    color: theme.colorScheme.primary,
                    size: 32,
                  ),
                  const SizedBox(width: SchoolWayTheme.spacing12),
                  Expanded(
                    child: Text(
                      localizations.csvRecordsTotal(totalRows),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SchoolWayTheme.spacing12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: const BorderRadius.all(
                Radius.circular(SchoolWayTheme.radius),
              ),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              children: [
                for (var index = 0; index < statuses.length; index++) ...[
                  _CsvPreviewStatusRow(status: statuses[index]),
                  if (index != statuses.length - 1)
                    const Divider(height: 1, indent: 52),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CsvPreviewStatus {
  const _CsvPreviewStatus({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _CsvPreviewStatusRow extends StatelessWidget {
  const _CsvPreviewStatusRow({required this.status});

  final _CsvPreviewStatus status;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: '${status.label}: ${status.value}',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SchoolWayTheme.spacing16,
              vertical: SchoolWayTheme.spacing12,
            ),
            child: Row(
              children: [
                Icon(status.icon, color: status.color, size: 24),
                const SizedBox(width: SchoolWayTheme.spacing12),
                Expanded(
                  child: Text(
                    status.label,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: SchoolWayTheme.spacing12),
                Text(
                  '${status.value}',
                  style: textTheme.titleLarge?.copyWith(
                    color: status.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
