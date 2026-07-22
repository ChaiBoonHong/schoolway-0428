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

  /// Initialize Hive box and listen for connectivity recovery.
  static Future<void> init() async {
    try {
      if (!Hive.isBoxOpen(_boxName)) {
        _box = await Hive.openBox(_boxName);
      } else {
        _box = Hive.box(_boxName);
      }

      _connectivitySub?.cancel();
      _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
        final hasConnection = results.any((r) => r != ConnectivityResult.none);
        if (hasConnection && !_isSyncing) {
          flushQueue();
        }
      });

      // Initial check
      flushQueue();
    } catch (e) {
      debugPrint('OfflineQueueService init error: $e');
    }
  }

  /// Queue an event map locally when offline or when network write fails.
  static Future<void> enqueueEvent(Map<String, dynamic> eventData) async {
    await init();
    final key = DateTime.now().millisecondsSinceEpoch.toString();
    await _box?.put(key, eventData);
    debugPrint('Event queued locally: $key');
  }

  /// Returns count of pending offline events.
  static int get pendingCount => _box?.length ?? 0;

  /// Flush queued events sequentially to Firestore.
  static Future<void> flushQueue() async {
    if (_box == null || _box!.isEmpty || _isSyncing) return;
    _isSyncing = true;

    try {
      final keys = _box!.keys.toList();
      for (final key in keys) {
        final raw = _box!.get(key);
        if (raw is Map) {
          final data = Map<String, dynamic>.from(raw);
          try {
            final locationMap = data['location'] is Map
                ? Map<String, dynamic>.from(data['location'] as Map)
                : <String, dynamic>{};
            final event = BoardingEvent(
              id: '',
              studentId: data['studentId'] ?? '',
              busId: data['busId'] ?? '',
              driverId: data['driverId'] ?? '',
              sessionId: data['sessionId'],
              eventType: data['eventType'] ?? 'board',
              location: EventLocation.fromMap(locationMap),
              timestamp: data['timestamp'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int)
                  : DateTime.now(),
              nfcCardId: data['nfcCardId'],
              synced: true,
              isManual: data['isManual'] ?? false,
              manualNote: data['manualNote'],
            );

            await FirebaseService.createBoardingEvent(event);
            await _box!.delete(key);
            debugPrint('Offline event synced and removed: $key');
          } catch (e) {
            debugPrint('Failed syncing queued event $key: $e');
            // Retain key for next retry
            break;
          }
        }
      }
    } finally {
      _isSyncing = false;
    }
  }
}
