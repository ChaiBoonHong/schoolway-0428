import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'package:schoolway/core/diagnostics/diagnostic_event.dart';
import 'package:schoolway/core/diagnostics/diagnostic_share_service.dart';
import 'package:schoolway/core/preferences/app_preferences.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/features/shell/onboarding_screen.dart';
import 'package:schoolway/l10n/app_localizations.dart';

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final preferences = ref.watch(appPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Semantics(
            header: true,
            child: Text(
              strings.appearance,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ThemeMode>(
            initialValue: preferences.themeMode,
            decoration: InputDecoration(labelText: strings.theme),
            items: [
              DropdownMenuItem(
                value: ThemeMode.system,
                child: Text(strings.themeSystem),
              ),
              DropdownMenuItem(
                value: ThemeMode.light,
                child: Text(strings.themeLight),
              ),
              DropdownMenuItem(
                value: ThemeMode.dark,
                child: Text(strings.themeDark),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                ref.read(appPreferencesProvider.notifier).setThemeMode(value);
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<MotionPreference>(
            initialValue: preferences.motionPreference,
            decoration: InputDecoration(labelText: strings.motion),
            items: [
              DropdownMenuItem(
                value: MotionPreference.system,
                child: Text(strings.motionSystem),
              ),
              DropdownMenuItem(
                value: MotionPreference.reduced,
                child: Text(strings.motionReduced),
              ),
              DropdownMenuItem(
                value: MotionPreference.full,
                child: Text(strings.motionFull),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                ref
                    .read(appPreferencesProvider.notifier)
                    .setMotionPreference(value);
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: preferences.locale.languageCode,
            decoration: InputDecoration(labelText: strings.language),
            items: [
              DropdownMenuItem(value: 'en', child: Text(strings.english)),
            ],
            onChanged: (value) {
              if (value != null) {
                ref
                    .read(appPreferencesProvider.notifier)
                    .setLocale(Locale(value));
              }
            },
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.slideshow_outlined),
            label: Text(strings.viewOnboardingAgain),
            onPressed: () async {
              await ref
                  .read(appPreferencesProvider.notifier)
                  .showOnboardingAgain();
              if (!context.mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const OnboardingScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: SchoolWayTheme.spacing32),
          const Divider(),
          const SizedBox(height: SchoolWayTheme.spacing24),
          const _DiagnosticsSection(),
        ],
      ),
    );
  }
}

class _DiagnosticsSection extends StatefulWidget {
  const _DiagnosticsSection();

  @override
  State<_DiagnosticsSection> createState() => _DiagnosticsSectionState();
}

class _DiagnosticsSectionState extends State<_DiagnosticsSection> {
  late Future<DiagnosticSummary> _summary = AppLogger.summary();
  bool _working = false;

  void _refresh() => setState(() => _summary = AppLogger.summary());

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              strings.diagnostics,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: SchoolWayTheme.spacing8),
          Text(strings.diagnosticsDescription),
          const SizedBox(height: SchoolWayTheme.spacing16),
          FutureBuilder<DiagnosticSummary>(
            future: _summary,
            builder: (context, snapshot) {
              final summary = snapshot.data;
              if (summary == null) {
                return const LinearProgressIndicator();
              }
              final material = MaterialLocalizations.of(context);
              return Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.eventCount == 0
                          ? strings.noDiagnosticEvents
                          : strings.diagnosticEventCount(
                              summary.eventCount,
                              _formatBytes(summary.bytes),
                            ),
                    ),
                    if (summary.oldest != null && summary.newest != null)
                      Text(
                        strings.diagnosticRange(
                          material.formatCompactDate(summary.oldest!.toLocal()),
                          material.formatCompactDate(summary.newest!.toLocal()),
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: SchoolWayTheme.spacing16),
          FilledButton.icon(
            onPressed: _working
                ? null
                : () async {
                    setState(() => _working = true);
                    try {
                      final shared =
                          await DiagnosticShareService.exportAndShare();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            shared
                                ? strings.diagnosticLogReady
                                : strings.diagnosticLogDownloaded,
                          ),
                        ),
                      );
                    } finally {
                      if (mounted) setState(() => _working = false);
                    }
                  },
            icon: const Icon(Icons.ios_share_outlined),
            label: Text(strings.shareDiagnosticLog),
          ),
          const SizedBox(height: SchoolWayTheme.spacing8),
          OutlinedButton.icon(
            onPressed: _working
                ? null
                : () async {
                    setState(() => _working = true);
                    try {
                      final saved =
                          await DiagnosticShareService.saveOrDownload();
                      if (!context.mounted || !saved) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(strings.diagnosticLogDownloaded),
                        ),
                      );
                    } finally {
                      if (mounted) setState(() => _working = false);
                    }
                  },
            icon: const Icon(Icons.download_outlined),
            label: Text(strings.saveDiagnosticLog),
          ),
          const SizedBox(height: SchoolWayTheme.spacing8),
          OutlinedButton.icon(
            onPressed: () async {
              final summary = await AppLogger.summary();
              final incident = summary.latestIncidentId;
              if (!context.mounted) return;
              if (incident == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(strings.noIncidentReference)),
                );
                return;
              }
              await Clipboard.setData(ClipboardData(text: incident));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(strings.incidentReferenceCopied)),
              );
            },
            icon: const Icon(Icons.copy_outlined),
            label: Text(strings.copyIncidentReference),
          ),
          const SizedBox(height: SchoolWayTheme.spacing8),
          TextButton.icon(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(strings.clearDiagnosticHistory),
                  content: Text(strings.clearDiagnosticHistoryConfirmation),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(strings.cancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(strings.clear),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              await AppLogger.clear();
              if (!context.mounted) return;
              _refresh();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(strings.diagnosticHistoryCleared)),
              );
            },
            icon: const Icon(Icons.delete_outline),
            label: Text(strings.clearDiagnosticHistory),
          ),
        ],
      ),
    );
  }
}
