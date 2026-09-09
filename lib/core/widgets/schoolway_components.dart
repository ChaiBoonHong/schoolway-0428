import 'package:flutter/material.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';

class SchoolWayPageHeader extends StatelessWidget {
  const SchoolWayPageHeader({
    required this.title,
    this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: SchoolWayTheme.spacing4),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
      ?action,
    ],
  );
}

class SchoolWaySectionCard extends StatelessWidget {
  const SchoolWaySectionCard({required this.child, this.title, super.key});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(SchoolWayTheme.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Semantics(
              header: true,
              child: Text(
                title!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: SchoolWayTheme.spacing12),
          ],
          child,
        ],
      ),
    ),
  );
}

class SchoolWayFormSection extends StatelessWidget {
  const SchoolWayFormSection({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SchoolWaySectionCard(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const SizedBox(height: SchoolWayTheme.spacing12),
          children[index],
        ],
      ],
    ),
  );
}

class SchoolWayPrimaryButton extends StatelessWidget {
  const SchoolWayPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => icon == null
      ? FilledButton(onPressed: onPressed, child: Text(label))
      : FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        );
}

class SchoolWaySecondaryButton extends StatelessWidget {
  const SchoolWaySecondaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => icon == null
      ? OutlinedButton(onPressed: onPressed, child: Text(label))
      : OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        );
}

class SchoolWayDestructiveButton extends StatelessWidget {
  const SchoolWayDestructiveButton({
    required this.label,
    required this.onPressed,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    style: FilledButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.error,
      foregroundColor: Theme.of(context).colorScheme.onError,
    ),
    onPressed: onPressed,
    icon: const Icon(Icons.delete_outline),
    label: Text(label),
  );
}

enum SchoolWayStatus { success, warning, danger, info }

class SchoolWayStatusBadge extends StatelessWidget {
  const SchoolWayStatusBadge({
    required this.label,
    required this.status,
    super.key,
  });
  final String label;
  final SchoolWayStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.schoolWayColors;
    final (color, icon) = switch (status) {
      SchoolWayStatus.success => (
        colors.badgeSuccess,
        Icons.check_circle_outline,
      ),
      SchoolWayStatus.warning => (
        colors.badgeWarning,
        Icons.warning_amber_outlined,
      ),
      SchoolWayStatus.danger => (colors.badgeDanger, Icons.error_outline),
      SchoolWayStatus.info => (colors.badgeInfo, Icons.info_outline),
    };
    final bgAlpha = context.isDarkMode ? 0.18 : 0.08;
    return Semantics(
      label: label,
      child: Chip(
        avatar: Icon(icon, color: color, size: 18),
        label: Text(
          label,
          style: TextStyle(
            color: color,
            fontFamily: 'Lexend',
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: color.withValues(alpha: bgAlpha),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      ),
    );
  }
}

enum SchoolWayStateKind { empty, loading, error }

class SchoolWayStateView extends StatelessWidget {
  const SchoolWayStateView({
    required this.kind,
    required this.message,
    this.onRetry,
    super.key,
  });
  final SchoolWayStateKind kind;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (kind == SchoolWayStateKind.loading) {
      return Semantics(
        label: message,
        liveRegion: true,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final icon = kind == SchoolWayStateKind.error
        ? Icons.error_outline
        : Icons.inbox_outlined;
    return Center(
      child: Semantics(
        liveRegion: kind == SchoolWayStateKind.error,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: SchoolWayTheme.spacing12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: SchoolWayTheme.spacing12),
              IconButton(
                onPressed: onRetry,
                tooltip: 'Retry',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<bool> showSchoolWayConfirmation({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelLabel),
          ),
          destructive
              ? SchoolWayDestructiveButton(
                  label: confirmLabel,
                  onPressed: () => Navigator.pop(context, true),
                )
              : SchoolWayPrimaryButton(
                  label: confirmLabel,
                  onPressed: () => Navigator.pop(context, true),
                ),
        ],
      ),
    ) ??
    false;
