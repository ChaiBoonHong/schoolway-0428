import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';

class AppPermissions {
  static Future<void> requestEssentialPermissions() async {
    try {
      await _ensureLocationPermission();
    } catch (e) {
      debugPrint('Permissions: location check failed: $e');
    }
    try {
      await _ensureNotificationPermission();
    } catch (e) {
      debugPrint('Permissions: notification check failed: $e');
    }
  }

  static Future<void> _ensureLocationPermission() async {
    if (kIsWeb) {
      // Do not request location on web startup. Let specific features request it when needed.
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
  }

  static Future<void> _ensureNotificationPermission() async {
    if (kIsWeb) {
      // Do not eagerly request notification permission on web startup.
      // PushMessagingService will handle it when the user logs in.
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
  }
}
