import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/models.dart';
import 'firebase_service.dart';

/// Manages offline queueing of attendance and operational events using Hive,
/// auto-flushing to Firestore when connectivity is restored.
class OfflineQueueService {
  static const String _boxName = 'offline_events_box';
  static Box? _box;
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  static bool _isSyncing = false;

  static Timer? _retryTimer;
  static int _retryDelayMinutes = 1;
  static const int _maxRetryDelayMinutes = 60;

  /// Notifier for the number of pending offline events
  static final ValueNotifier<int> pendingCountNotifier = ValueNotifier(0);

  /// Initialize Hive box and listen for connectivity recovery.
  static Future<void> init() async {
    try {
      if (!Hive.isBoxOpen(_boxName)) {
        _box = await Hive.openBox(_boxName);
      } else {
        _box = Hive.box(_boxName);
      }

      _updateNotifier();

      _connectivitySub?.cancel();
      _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
        final hasConnection = results.any((r) => r != ConnectivityResult.none);
        if (hasConnection && !_isSyncing) {
          _retryDelayMinutes = 1; // Reset backoff on reconnect
          flushQueue();
        }
      });

      _retryTimer?.cancel();
      _retryTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
        if (pendingCount > 0 && !_isSyncing) {
          // Implementing exponential backoff timing logic roughly
          if (timer.tick % _retryDelayMinutes == 0) {
            flushQueue();
          }
        }
      });

      // Initial check
      flushQueue();
    } catch (e) {
      debugPrint('OfflineQueueService init error: $e');
    }
  }

  static void _updateNotifier() {
    pendingCountNotifier.value = pendingCount;
  }

  /// Queue an event map locally when offline or when network write fails.
  static Future<void> enqueueEvent(
    Map<String, dynamic> eventData, {
    String type = 'boarding',
  }) async {
    await init();
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    eventData['_queueType'] = type;
    await _box?.put(key, eventData);
    _updateNotifier();
    debugPrint('Event queued locally: $key (type: $type)');
  }

  /// Returns count of pending offline events.
  static int get pendingCount => _box?.length ?? 0;

  /// Flush queued events sequentially to Firestore.
  static Future<void> flushQueue() async {
    if (_box == null || _box!.isEmpty || _isSyncing) return;
    _isSyncing = true;

    try {
      final keys = _box!.keys.toList();
      bool anyFailed = false;

      for (final key in keys) {
        final raw = _box!.get(key);
        if (raw is Map) {
          final data = Map<String, dynamic>.from(raw);
          final queueType = data['_queueType'] as String? ?? 'boarding';

          try {
            if (queueType == 'boarding') {
              final locationMap = data['location'] is Map
                  ? Map<String, dynamic>.from(data['location'] as Map)
                  : <String, dynamic>{};
              final event = BoardingEvent(
                id: '',
                studentId: data['studentId'] ?? '',
                busId: data['busId'] ?? '',
                driverUid: data['driverUid'] ?? '',
                sessionId: data['sessionId'],
                eventType: data['eventType'] ?? 'board',
                location: EventLocation.fromMap(locationMap),
                timestamp: data['timestamp'] != null
                    ? DateTime.fromMillisecondsSinceEpoch(
                        data['timestamp'] as int,
                      )
                    : DateTime.now(),
                nfcCardId: data['nfcCardId'],
                synced: true,
                isManual: data['isManual'] ?? false,
                manualNote: data['manualNote'],
              );
              await FirebaseService.createBoardingEvent(event);
            } else if (queueType == 'correction') {
              final correction = AttendanceCorrection(
                id: data['id'] ?? '',
                originalEventId: data['originalEventId'] ?? '',
                studentId: data['studentId'] ?? '',
                correctedBy: data['correctedByUid'] ?? '',
                oldEventType: data['oldEventType'] ?? '',
                newEventType: data['newEventType'] ?? '',
                reason: data['reason'] ?? '',
                timestamp: data['timestamp'] != null
                    ? DateTime.fromMillisecondsSinceEpoch(
                        data['timestamp'] as int,
                      )
                    : DateTime.now(),
              );
              await FirebaseService.recordAttendanceCorrection(correction);
            } else if (queueType == 'incident') {
              final incident = IncidentReport(
                id: data['id'] ?? '',
                driverUid: data['driverUid'] ?? '',
                busId: data['busId'] ?? '',
                sessionId: data['sessionId'],
                category: data['category'] ?? 'General',
                description: data['description'] ?? '',
                severity: data['severity'] ?? 'Medium',
                timestamp: data['timestamp'] != null
                    ? DateTime.fromMillisecondsSinceEpoch(
                        data['timestamp'] as int,
                      )
                    : DateTime.now(),
                resolved: data['resolved'] ?? false,
              );
              await FirebaseService.createIncidentReport(incident);
            }

            await _box!.delete(key);
            _updateNotifier();
            debugPrint('Offline event synced and removed: $key');
          } catch (e) {
            debugPrint('Failed syncing queued event $key: $e');
            anyFailed = true;
            break; // Stop syncing and retain key for next retry
          }
        }
      }

      if (anyFailed) {
        // Exponential backoff
        _retryDelayMinutes = (_retryDelayMinutes * 2).clamp(
          1,
          _maxRetryDelayMinutes,
        );
      } else {
        // Success
        _retryDelayMinutes = 1;
      }
    } finally {
      _isSyncing = false;
    }
  }
}
