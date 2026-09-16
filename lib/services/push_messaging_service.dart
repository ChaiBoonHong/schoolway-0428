import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

import 'package:schoolway/core/config.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
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
  static const _normalChannelId = 'schoolway_channel_id';
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
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );
        const initSettings = InitializationSettings(
          android: androidInit,
          iOS: iosInit,
        );
        await _localNotifications.initialize(settings: initSettings);
        final android = _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            _normalChannelId,
            'SchoolWay Notifications',
            description: 'Notifications from SchoolWay',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'notifications',
        'Local notification setup was unavailable.',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (!kIsWeb) {
      try {
        await _requestPermissionIfNeeded();
      } catch (error, stackTrace) {
        AppLogger.warning(
          'notifications',
          'Initial notification permission request failed.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    FirebaseMessaging.onMessage.listen(
      (message) {
        AppLogger.debug(
          'notifications',
          'A foreground push notification was received.',
        );
        unawaited(_showForegroundPush(message));
      },
      onError: (Object error, StackTrace stackTrace) => AppLogger.warning(
        'notifications',
        'Foreground push monitoring failed.',
        error: error,
        stackTrace: stackTrace,
      ),
    );

    _authSub = FirebaseAuth.instance.authStateChanges().listen(
      (user) {
        if (user != null) {
          // Rotate the token when an account becomes active. This repairs
          // installations whose cached FCM token was invalidated while the
          // app was closed, which otherwise may not emit onTokenRefresh.
          unawaited(_syncTokenForUid(user.uid, forceRefresh: true));
          unawaited(_listenInAppNotifications(user.uid));
          unawaited(_enableCriticalAlertsForUid(user.uid));
        } else {
          unawaited(_inAppSub?.cancel());
          _inAppSub = null;
          _seenNotificationIds.clear();
          _inAppSeeded = false;
        }
      },
      onError: (Object error, StackTrace stackTrace) => AppLogger.error(
        'authentication',
        'Authentication state monitoring failed.',
        error: error,
        stackTrace: stackTrace,
      ),
    );

    FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) async {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;
        await _persistToken(user.uid, token);
      },
      onError: (Object error, StackTrace stackTrace) => AppLogger.warning(
        'notifications',
        'Notification token refresh monitoring failed.',
        error: error,
        stackTrace: stackTrace,
      ),
    );
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
    _inAppSub = FirebaseService.notificationsForAuthUid(authUid).listen(
      (notifications) async {
        if (!_inAppSeeded) {
          _seenNotificationIds.addAll(notifications.map((n) => n.id));
          _inAppSeeded = true;
          return;
        }

        // Android/iOS notification delivery comes directly from FCM. Keep the
        // Firestore stream for the inbox state only; showing it here as well
        // caused duplicate foreground alerts and made delivery depend on a
        // Firestore listener.
        if (!kIsWeb) return;

        var preferences = const NotificationPreferences();
        try {
          preferences = await FirebaseService.getNotificationPreferences(
            authUid: authUid,
          );
        } catch (error, stackTrace) {
          AppLogger.warning(
            'notifications',
            'Notification preferences were unavailable; defaults were used.',
            error: error,
            stackTrace: stackTrace,
          );
        }

        for (final notification in notifications) {
          if (!_seenNotificationIds.add(notification.id)) continue;

          final category = notification.category.toLowerCase();
          if (preferences.isInQuietHours(DateTime.now()) &&
              category != 'emergency' &&
              category != 'route_deviation') {
            continue;
          }
          if (category != 'emergency' &&
              category != 'boarding' &&
              category != 'dropoff' &&
              category != 'route_deviation') {
            continue;
          }

          if (kIsWeb) {
            if (webPushGranted) {
              browser_notification.showBrowserNotification(
                title: notification.title,
                body: notification.body,
              );
            }
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error(
          'notifications',
          'In-app notification monitoring failed.',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  static Future<void> _showForegroundPush(RemoteMessage message) async {
    if (kIsWeb) return;
    final title = message.notification?.title ?? 'SchoolWay';
    final body = message.notification?.body ?? '';
    final isCritical = message.data['isCritical'] == 'true';
    await _localNotifications.show(
      id: (message.messageId ?? message.data['notificationId'] ?? title)
          .hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          isCritical ? _emergencyChannelId : _normalChannelId,
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

  static Future<bool> areSystemNotificationsEnabled() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.areNotificationsEnabled() ?? false;
  }

  /// Requests notification permission after an authenticated user explicitly
  /// enables notifications from the in-app settings screen.
  static Future<bool> requestNotificationPermission() async {
    final settings = await _requestPermission();
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (granted && uid != null) await _syncTokenForUid(uid);
    return granted;
  }

  static Future<void> _requestPermissionIfNeeded() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.notDetermined) {
      return;
    }
    await _requestPermission();
  }

  static Future<NotificationSettings> _requestPermission() {
    return FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
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
    if (android == null) return false;
    final granted = await android.requestNotificationPolicyAccess() ?? false;
    if (granted) await _createCriticalChannel(android);
    return granted;
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
    await _createCriticalChannel(android);
  }

  static Future<void> _createCriticalChannel(
    AndroidFlutterLocalNotificationsPlugin android,
  ) {
    return android.createNotificationChannel(
      const AndroidNotificationChannel(
        _emergencyChannelId,
        'Critical alerts',
        description: 'SchoolWay alerts selected for critical delivery',
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
    } catch (error, stackTrace) {
      AppLogger.warning(
        'notifications',
        'Notification permission state could not be read.',
        error: error,
        stackTrace: stackTrace,
      );
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

  static Future<void> _syncTokenForUid(
    String authUid, {
    bool forceRefresh = false,
  }) async {
    try {
      if (!await _canRegisterFcmToken()) {
        if (kDebugMode) {
          AppLogger.debug('notifications', 'Push registration was skipped.');
        }
        return;
      }

      String? previousToken;
      if (forceRefresh) {
        try {
          previousToken = await _getToken();
          if (previousToken != null && previousToken.isNotEmpty) {
            await FirebaseMessaging.instance.deleteToken();
          }
        } catch (error, stackTrace) {
          // A failed rotation should not prevent normal token registration.
          AppLogger.warning(
            'notifications',
            'Cached notification token could not be refreshed.',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      final token = await _getToken();
      if (previousToken != null && previousToken != token) {
        try {
          await FirebaseService.deleteFcmTokenForAuthUid(
            authUid,
            previousToken,
          );
        } catch (error, stackTrace) {
          // The new token remains usable even if cleanup is temporarily
          // unavailable. The backend removes invalid tokens after delivery.
          AppLogger.warning(
            'notifications',
            'Previous notification token cleanup failed.',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      await _persistToken(authUid, token);
    } catch (error, stackTrace) {
      if (_isPermissionDeniedError(error)) {
        if (kDebugMode) {
          AppLogger.debug('notifications', 'Push registration was denied.');
        }
        return;
      }
      AppLogger.warning(
        'notifications',
        'Push registration failed.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<String?> _getToken() async {
    if (kIsWeb) {
      final vapid = AppConfig.fcmWebVapidKey.trim();
      if (vapid.isEmpty) {
        AppLogger.warning(
          'notifications',
          'Web push registration is not configured.',
        );
        return null;
      }
      return FirebaseMessaging.instance.getToken(vapidKey: vapid);
    }
    return FirebaseMessaging.instance.getToken();
  }

  static Future<void> _persistToken(String authUid, String? token) async {
    if (token == null || token.isEmpty) return;
    await FirebaseService.updateFcmTokenForAuthUid(authUid, token);
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
