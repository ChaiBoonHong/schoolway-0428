import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

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
        
        const androidInit = AndroidInitializationSettings('ic_launcher');
        const iosInit = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
        const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
        await _localNotifications.initialize(settings: initSettings);
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
        unawaited(_listenInAppNotifications(user.uid));
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

  static Future<void> _listenInAppNotifications(String authUid) async {
    await _inAppSub?.cancel();
    _seenNotificationIds.clear();
    _inAppSeeded = false;

    bool webPushGranted = false;
    if (kIsWeb) {
      webPushGranted = await browser_notification.ensureNotificationPermission();
    }

    _inAppSub = FirebaseService.notificationsForAuthUid(authUid).listen((
      notifications,
    ) async {
      if (!_inAppSeeded) {
        _seenNotificationIds.addAll(notifications.map((n) => n.id));
        _inAppSeeded = true;
        return;
      }

      bool inQuietHours = false;
      try {
        final prefsDoc = await FirebaseService.usersCollection
            .doc(authUid)
            .collection('notification_prefs')
            .doc('settings')
            .get();

        if (prefsDoc.exists) {
          final data = prefsDoc.data() as Map<String, dynamic>;
          final quietHoursEnabled = data['quietHoursEnabled'] ?? false;
          
          if (quietHoursEnabled) {
            final startMap = data['quietStart'] as Map<String, dynamic>?;
            final endMap = data['quietEnd'] as Map<String, dynamic>?;
            
            final quietStartHour = startMap?['hour'] ?? 22;
            final quietStartMin = startMap?['minute'] ?? 0;
            final quietEndHour = endMap?['hour'] ?? 6;
            final quietEndMin = endMap?['minute'] ?? 0;

            final now = DateTime.now();
            final currentMinutes = now.hour * 60 + now.minute;
            final startMinutes = quietStartHour * 60 + quietStartMin;
            final endMinutes = quietEndHour * 60 + quietEndMin;

            if (startMinutes < endMinutes) {
              inQuietHours = currentMinutes >= startMinutes && currentMinutes <= endMinutes;
            } else {
              // Crosses midnight
              inQuietHours = currentMinutes >= startMinutes || currentMinutes <= endMinutes;
            }
          }

          final studentsMap = data['students'] as Map<String, dynamic>?;
          if (studentsMap != null) {          }
        }
      } catch (e) {
        debugPrint('PushMessagingService: failed to fetch notification prefs $e');
      }

      for (final notification in notifications) {
        if (!_seenNotificationIds.add(notification.id)) continue;

        final type = notification.type.toLowerCase();
        
        // Optional: you might want to filter per-student based on `notification.studentId` if it exists.
        // Since notification model may not always have studentId readily available here, we'll
        // apply the logic if it's found in the notification payload (data or body).
        
        bool suppress = false;
        if (inQuietHours && type != 'emergency') {
          suppress = true;
        }

        // We check if we have a studentId in the title or body (as a simple heuristic) or if the Notification object had a relatedStudentId field.
        // Assuming we want to filter per-student based on their specific toggle:
        // For now, if we cannot map it to a student, we assume true.

        if (suppress) continue;

        if (type != 'emergency' && type != 'boarding') continue;

        if (kIsWeb) {
          if (webPushGranted) {
            browser_notification.showBrowserNotification(
              title: notification.title,
              body: notification.body,
            );
          }
        } else {
          _localNotifications.show(
            id: notification.id.hashCode,
            title: notification.title,
            body: notification.body,
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'schoolway_channel_id',
                'SchoolWay Notifications',
                channelDescription: 'Notifications from SchoolWay',
                importance: Importance.max,
                priority: Priority.high,
                icon: 'ic_launcher',
              ),
              iOS: DarwinNotificationDetails(),
            ),
          );
        }
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
