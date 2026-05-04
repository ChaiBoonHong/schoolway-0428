import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:schoolway/core/config.dart';
import 'package:schoolway/core/utils/browser_notification.dart'
    as browser_notification;
import 'package:schoolway/models/app_notification.dart';
import 'firebase_service.dart';

/// Registers FCM token on the signed-in user document (for future Cloud push).
/// In-app notifications use Firestore regardless of FCM.
class PushMessagingService {
  PushMessagingService._();

  static bool _initialized = false;
  static StreamSubscription<User?>? _authSub;
  static StreamSubscription<List<InAppNotification>>? _inAppSub;
  static final Set<String> _seenNotificationIds = <String>{};
  static bool _inAppSeeded = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      if (!kIsWeb) {
        await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (e) {
      debugPrint('PushMessagingService: notification setup: $e');
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('FCM foreground: ${message.notification?.title}');
    });

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        unawaited(_syncTokenForUid(user.uid));
        unawaited(_listenInAppNotificationsForWeb(user.uid));
      } else {
        unawaited(_inAppSub?.cancel());
        _inAppSub = null;
        _seenNotificationIds.clear();
        _inAppSeeded = false;
      }
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;
      await _persistToken(u.uid, token);
    });
  }

  static Future<void> _listenInAppNotificationsForWeb(String authUid) async {
    await _inAppSub?.cancel();
    _seenNotificationIds.clear();
    _inAppSeeded = false;

    if (!kIsWeb) return;
    if (!await browser_notification.ensureNotificationPermission()) return;

    _inAppSub = FirebaseService.notificationsForAuthUid(authUid).listen((
      notifications,
    ) {
      if (!_inAppSeeded) {
        _seenNotificationIds.addAll(notifications.map((n) => n.id));
        _inAppSeeded = true;
        return;
      }

      for (final notification in notifications) {
        if (!_seenNotificationIds.add(notification.id)) continue;

        // Show browser notifications for emergency and boarding/drop-off events
        // so parents receive immediate alerts even when away from inbox screen.
        final type = notification.type.toLowerCase();
        if (type != 'emergency' && type != 'boarding') continue;

        browser_notification.showBrowserNotification(
          title: notification.title,
          body: notification.body,
        );
      }
    });
  }

  /// True when the browser/OS allows showing notifications (not denied/blocked).
  static Future<bool> _canRegisterFcmToken() async {
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      final s = settings.authorizationStatus;
      return s == AuthorizationStatus.authorized ||
          s == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  static bool _isPermissionDeniedError(Object e) {
    if (e is FirebaseException) {
      final c = e.code.toLowerCase();
      return c.contains('permission');
    }
    return e.toString().toLowerCase().contains('permission-blocked');
  }

  static Future<void> _syncTokenForUid(String authUid) async {
    try {
      if (!await _canRegisterFcmToken()) {
        if (kDebugMode) {
          debugPrint(
            'PushMessagingService: FCM token skipped (notification permission denied or blocked).',
          );
        }
        return;
      }

      String? token;
      if (kIsWeb) {
        final vapid = AppConfig.fcmWebVapidKey.trim();
        if (vapid.isEmpty) {
          debugPrint(
            'PushMessagingService: set AppConfig.fcmWebVapidKey (Firebase Console → Web Push key) to register FCM on web.',
          );
          return;
        }
        token = await FirebaseMessaging.instance.getToken(vapidKey: vapid);
      } else {
        token = await FirebaseMessaging.instance.getToken();
      }
      await _persistToken(authUid, token);
    } catch (e) {
      if (_isPermissionDeniedError(e)) {
        if (kDebugMode) {
          debugPrint(
            'PushMessagingService: FCM token unavailable (notification permission denied or blocked).',
          );
        }
        return;
      }
      debugPrint('PushMessagingService: getToken failed: $e');
    }
  }

  static Future<void> _persistToken(String authUid, String? token) async {
    if (token == null || token.isEmpty) return;
    final username = await FirebaseService.getUsernameFromAuthUid(authUid);
    if (username == null) return;
    await FirebaseService.updateFcmTokenForUsername(username, token);
  }

  static Future<void> dispose() async {
    await _authSub?.cancel();
    await _inAppSub?.cancel();
    _authSub = null;
    _inAppSub = null;
    _seenNotificationIds.clear();
    _inAppSeeded = false;
  }
}
