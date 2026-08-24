import 'package:flutter/material.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'package:schoolway/core/diagnostics/diagnostic_share_service.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/l10n/app_localizations.dart';

class StartupRecoveryScreen extends StatefulWidget {
  const StartupRecoveryScreen({
    super.key,
    required this.incidentId,
    required this.onRetry,
  });

  final String incidentId;
  final Future<void> Function() onRetry;

  @override
  State<StartupRecoveryScreen> createState() => _StartupRecoveryScreenState();
}

class _StartupRecoveryScreenState extends State<StartupRecoveryScreen> {
  bool _retrying = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.all(SchoolWayTheme.spacing24),
                    child: Semantics(
                      liveRegion: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(height: SchoolWayTheme.spacing16),
                          Text(
                            strings.startupFailed,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: SchoolWayTheme.spacing8),
                          SelectableText(
                            strings.errorReference(widget.incidentId),
                          ),
                          const SizedBox(height: SchoolWayTheme.spacing24),
                          FilledButton.icon(
                            onPressed: _retrying
                                ? null
                                : () async {
                                    setState(() => _retrying = true);
                                    try {
                                      await widget.onRetry();
                                    } catch (error, stackTrace) {
                                      AppLogger.error(
                                        'startup',
                                        'Startup retry failed.',
                                        error: error,
                                        stackTrace: stackTrace,
                                      );
                                      if (mounted) {
                                        setState(() => _retrying = false);
                                      }
                                    }
                                  },
                            icon: _retrying
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                            label: Text(strings.tryAgain),
                          ),
                          const SizedBox(height: SchoolWayTheme.spacing12),
                          OutlinedButton.icon(
                            onPressed: DiagnosticShareService.exportAndShare,
                            icon: const Icon(Icons.description_outlined),
                            label: Text(strings.openDiagnostics),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
