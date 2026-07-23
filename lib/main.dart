import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:hive_flutter/hive_flutter.dart';
import 'services/offline_queue_service.dart';
import 'app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Hive.initFlutter();
    await OfflineQueueService.init();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );


    // Web: disable IndexedDB persistence to avoid Firestore JS "INTERNAL ASSERTION"
    // failures (watch/target pipeline) seen after writes like emergency_alerts.add().
    // Must run before any other Firestore usage.
    if (kIsWeb) {
      swFirestore.settings = const Settings(
        persistenceEnabled: false,
        ignoreUndefinedProperties: true,
      );
    }

    runApp(const SchoolWayApp());
  }, (error, stackTrace) {
    debugPrint('Uncaught startup error: $error');
    debugPrintStack(stackTrace: stackTrace);
  });
}
