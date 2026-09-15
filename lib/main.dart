import 'package:cloud_firestore/cloud_firestore.dart';v
import 'package:firebase_core/firebase_core.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';
import 'services/offline_queue_service.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'core/preferences/app_preferences.dart';
import 'core/diagnostics/app_logger.dart';
import 'core/theme/schoolway_theme.dart';
import 'features/shell/startup_recovery_screen.dart';
import 'l10n/app_localizations.dart';
import 'services/saved_accounts_store.dart';

Future<void> main() async {
  await runZonedGuarded(_runApplication, _handleUncaughtApplicationError);
}

Future<void> _runApplication() async {
  // The binding and every runApp call must be created in the same zone.
  // Otherwise Flutter can reject the first frame and leave the native splash
  // visible, especially on the first launch after installation.
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.initialize();

  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.error(
      'flutter',
      'Flutter framework error.',
      error: details.exception,
      stackTrace: details.stack ?? StackTrace.current,
    );
    if (kDebugMode) FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogger.fatal(
      'platform',
      'Uncaught platform error.',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };
  ErrorWidget.builder = (details) {
    final incidentId = AppLogger.error(
      'widget',
      'Widget build failed.',
      error: details.exception,
      stackTrace: details.stack ?? StackTrace.current,
    );
    return Builder(
      builder: (context) {
        final strings = AppLocalizations.of(context);
        return Semantics(
          liveRegion: true,
          label:
              '${strings.somethingWentWrong} ${strings.errorReference(incidentId)}',
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(SchoolWayTheme.spacing16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: SchoolWayTheme.spacing8),
                  Text(strings.somethingWentWrong),
                  SelectableText(strings.errorReference(incidentId)),
                ],
              ),
            ),
          ),
        );
      },
    );
  };

  try {
    await _bootstrap();
  } catch (error, stackTrace) {
    final incidentId = AppLogger.fatal(
      'startup',
      'Application startup failed.',
      error: error,
      stackTrace: stackTrace,
    );
    _runStartupRecovery(incidentId);
  }
}

void _handleUncaughtApplicationError(Object error, StackTrace stackTrace) {
  AppLogger.fatal(
    'application',
    'Uncaught application error.',
    error: error,
    stackTrace: stackTrace,
  );
}

void _runStartupRecovery(String incidentId) {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: SchoolWayTheme.light,
      darkTheme: SchoolWayTheme.dark,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: StartupRecoveryScreen(incidentId: incidentId, onRetry: _bootstrap),
    ),
  );
}

Future<void> _bootstrap() async {
  await Hive.initFlutter();
  await AppPreferencesStore.initialize();
  await SavedAccountsStore.initialize();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  // Web persistence stays disabled to avoid the Firestore JS watch assertion.
  if (kIsWeb) {
    swFirestore.settings = const Settings(
      persistenceEnabled: false,
      ignoreUndefinedProperties: true,
    );
  }
  await OfflineQueueService.init();
  AppLogger.info('lifecycle', 'Application startup completed.');
  runApp(const ProviderScope(child: SchoolWayApp()));
}
