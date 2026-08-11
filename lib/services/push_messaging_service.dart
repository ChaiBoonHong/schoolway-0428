import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

import 'package:schoolway/core/config.dart';
import 'package:schoolway/core/utils/browser_notification.dart'
    as browser_notification;
import 'package:schoolway/models/app_notification.dart';
import 'package:schoolway/models/notification_preferences.dart';
import 'firebase_service.dart';

/// Registers FCM token on the signed-in user document (for future Cloud push).
/// In-app notifications use Firestore regardless of FCM.
class PushMessagingService {
  PushMessagingService._();

  static const _emergencyChannelId = 'schoolway_emergency';
  static const _settingsChannel = MethodChannel('schoolway/settings');

  static bool _initialized = false;
  static StreamSubscription<User?>? _authSub;
  static StreamSubscription<List<InAppNotification>>? _inAppSub;
  static final Set<String> _seenNotificationIds = <String>{};
  static bool _inAppSeeded = false;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      if (!kIsWeb) {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
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
        const initSettings = InitializationSettings(
          android: androidInit,
          iOS: iosInit,
        );
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
        unawaited(_enableCriticalAlertsForUid(user.uid));
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
      webPushGranted = await browser_notification
          .ensureNotificationPermission();
    }
    final username = await FirebaseService.getUsernameFromAuthUid(authUid);

    _inAppSub = FirebaseService.notificationsForAuthUid(authUid).listen((
      notifications,
    ) async {
      if (!_inAppSeeded) {
        _seenNotificationIds.addAll(notifications.map((n) => n.id));
        _inAppSeeded = true;
        return;
      }

      var preferences = const NotificationPreferences();
      try {
        if (username != null) {
          preferences = await FirebaseService.getNotificationPreferences(
            username: username,
            authUid: authUid,
          );
        }
      } catch (e) {
        debugPrint(
          'PushMessagingService: failed to fetch notification prefs $e',
        );
      }

      for (final notification in notifications) {
        if (!_seenNotificationIds.add(notification.id)) continue;

        final category = notification.category.toLowerCase();
        if (preferences.isInQuietHours(DateTime.now()) &&
            category != 'emergency') {
          continue;
        }
        if (category != 'emergency' &&
            category != 'boarding' &&
            category != 'dropoff') {
          continue;
        }

        if (kIsWeb) {
          if (webPushGranted) {
            browser_notification.showBrowserNotification(
              title: notification.title,
              body: notification.body,
            );
          }
        } else {
          final isCritical = notification.isCritical;
          _localNotifications.show(
            id: notification.id.hashCode,
            title: notification.title,
            body: notification.body,
            notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails(
                isCritical ? _emergencyChannelId : 'schoolway_channel_id',
                isCritical ? 'Critical alerts' : 'SchoolWay Notifications',
                channelDescription: isCritical
                    ? 'Critical SchoolWay emergency alerts'
                    : 'Notifications from SchoolWay',
                importance: Importance.max,
                priority: isCritical ? Priority.max : Priority.high,
                channelBypassDnd: isCritical,
                category: isCritical ? AndroidNotificationCategory.alarm : null,
                icon: 'ic_launcher',
              ),
              iOS: DarwinNotificationDetails(
                interruptionLevel: isCritical
                    ? InterruptionLevel.timeSensitive
                    : null,
              ),
            ),
          );
        }
      }
    });
  }

  static Future<bool> areSystemNotificationsEnabled() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.areNotificationsEnabled() ?? false;
  }

  static Future<bool> hasCriticalAlertAccess() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.hasNotificationPolicyAccess() ?? false;
  }

  static Future<bool> requestCriticalAlertAccess() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationPolicyAccess() ?? false;
  }

  static Future<void> openSystemNotificationSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _settingsChannel.invokeMethod<void>('openNotificationSettings');
  }

  static Future<void> _enableCriticalAlertsForUid(String authUid) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final role = (await FirebaseService.getUserRoleByAuthUid(
      authUid,
    ))?.toLowerCase();
    if (role != 'admin' && role != 'administrator' && role != 'parent') return;

    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    var granted = await android.hasNotificationPolicyAccess() ?? false;
    if (!granted) {
      granted = await android.requestNotificationPolicyAccess() ?? false;
    }
    if (!granted) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _emergencyChannelId,
        'Emergency alerts',
        description: 'Critical SchoolWay emergency alerts',
        importance: Importance.max,
        bypassDnd: true,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  /// True when the browser/OS allows showing notifications (not denied/blocked).
  static Future<bool> _canRegisterFcmToken() async {
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
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
