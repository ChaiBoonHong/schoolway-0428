import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/diagnostics/app_failure.dart';
import '../core/diagnostics/app_logger.dart';
import '../models/models.dart';
import 'firebase_service.dart';

enum OfflineReachability { checking, online, offline }

/// Manages offline queueing of attendance and operational events using Hive,
/// auto-flushing to Firestore when connectivity is restored.
class OfflineQueueService {
  static const String _boxName = 'offline_events_box';
  static Box? _box;
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  static bool _isSyncing = false;
  static bool _hasNetworkInterface = false;
  static Future<bool> Function()? _reachabilityOverride;

  static Timer? _retryTimer;
  static int _retryDelayMinutes = 1;
  static const int _maxRetryDelayMinutes = 60;

  /// Notifier for the number of pending offline events
  static final ValueNotifier<int> pendingCountNotifier = ValueNotifier(0);
  static final ValueNotifier<bool?> isOnlineNotifier = ValueNotifier(null);
  static final ValueNotifier<OfflineReachability> reachabilityNotifier =
      ValueNotifier(OfflineReachability.checking);

  @visibleForTesting
  static bool hasConnection(Iterable<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  @visibleForTesting
  static void setTestBox(Box? box) {
    _box = box;
    _isSyncing = false;
    isOnlineNotifier.value = null;
    reachabilityNotifier.value = OfflineReachability.checking;
    _updateNotifier();
  }

  @visibleForTesting
  static void setTestReachabilityCheck(Future<bool> Function()? check) {
    _reachabilityOverride = check;
    if (check != null) _hasNetworkInterface = true;
  }

  static void _setReachability(OfflineReachability state) {
    reachabilityNotifier.value = state;
    isOnlineNotifier.value = switch (state) {
      OfflineReachability.online => true,
      OfflineReachability.offline => false,
      OfflineReachability.checking => null,
    };
  }

  static Future<bool> _verifyReachability() async {
    if (!_hasNetworkInterface) {
      _setReachability(OfflineReachability.offline);
      return false;
    }
    _setReachability(OfflineReachability.checking);
    try {
      final reachable =
          await (_reachabilityOverride?.call() ??
                  FirebaseService.checkReachability())
              .timeout(const Duration(seconds: 8));
      _setReachability(
        reachable ? OfflineReachability.online : OfflineReachability.offline,
      );
      return reachable;
    } catch (_) {
      _setReachability(OfflineReachability.offline);
      return false;
    }
  }

  /// Initialize Hive box and listen for connectivity recovery.
  static Future<void> init() async {
    try {
      if (!Hive.isBoxOpen(_boxName)) {
        _box = await Hive.openBox(_boxName);
      } else {
        _box = Hive.box(_boxName);
      }

      _updateNotifier();

      final initialConnectivity = await Connectivity().checkConnectivity();
      _hasNetworkInterface = hasConnection(initialConnectivity);
      await _verifyReachability();

      _connectivitySub?.cancel();
      _connectivitySub = Connectivity().onConnectivityChanged.listen(
        (results) {
          _hasNetworkInterface = hasConnection(results);
          if (!_hasNetworkInterface) {
            _setReachability(OfflineReachability.offline);
          } else if (!_isSyncing) {
            _retryDelayMinutes = 1;
            unawaited(_syncAfterConnectivityRestored());
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          AppLogger.warning(
            'offline_sync',
            'Connectivity monitoring failed; periodic retry remains active.',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );

      _retryTimer?.cancel();
      _retryTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
        if (pendingCount > 0 && !_isSyncing) {
          if (timer.tick % _retryDelayMinutes == 0) {
            unawaited(flushQueue());
          }
        }
      });

      if (reachabilityNotifier.value == OfflineReachability.online) {
        unawaited(flushQueue());
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'offline_sync',
        'Offline queue initialization failed; operations remain online-only.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static void _updateNotifier() {
    pendingCountNotifier.value = pendingCount;
  }

  static Future<void> _syncAfterConnectivityRestored() async {
    await retryNow();
    if (pendingCount == 0) return;
    await Future<void>.delayed(const Duration(seconds: 3));
    await retryNow();
  }

  /// Queue an event map locally when offline or when network write fails.
  static Future<void> enqueueEvent(
    Map<String, dynamic> eventData, {
    String type = 'boarding',
  }) async {
    await init();
    final id = (eventData['id'] ?? '').toString().trim();
    final key = '$type:${id.isNotEmpty ? id : UniqueKey().toString()}';
    final queued = Map<String, dynamic>.from(eventData)
      ..['_queueType'] = type
      ..['_attemptCount'] = 0
      ..['_lastAttemptAt'] = null
      ..['_nextAttemptAt'] = null
      ..['_failureCategory'] = null
      ..['_incidentId'] = null;
    await _box?.put(key, queued);
    _updateNotifier();
    AppLogger.info('offline_sync', 'An operation was queued for later sync.');
  }

  /// Returns count of pending offline events.
  static int get pendingCount => _box?.length ?? 0;

  /// Queued attendance events for optimistic driver UI. These remain marked
  /// unsynced until the matching Firestore document is observed.
  static List<BoardingEvent> pendingBoardingEvents({
    required String sessionId,
    required String driverUid,
  }) {
    final box = _box;
    if (box == null) return const [];
    final events = <BoardingEvent>[];
    for (final raw in box.values) {
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      if ((data['_queueType'] as String? ?? 'boarding') != 'boarding' ||
          data['sessionId'] != sessionId ||
          data['driverUid'] != driverUid) {
        continue;
      }
      final locationMap = data['location'] is Map
          ? Map<String, dynamic>.from(data['location'] as Map)
          : <String, dynamic>{};
      events.add(
        BoardingEvent(
          id: data['id'] ?? '',
          studentId: data['studentId'] ?? '',
          busId: data['busId'] ?? '',
          driverUid: data['driverUid'] ?? '',
          sessionId: data['sessionId'],
          eventType: data['eventType'] ?? 'board',
          location: EventLocation.fromMap(locationMap),
          timestamp: data['timestamp'] is int
              ? DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int)
              : DateTime.now(),
          nfcCardId: data['nfcCardId'],
          synced: false,
          isManual: data['isManual'] ?? false,
          manualNote: data['manualNote'],
        ),
      );
    }
    return events;
  }

  /// Makes all retained operations eligible immediately and starts a sync.
  static Future<void> retryNow() async {
    final box = _box;
    if (box == null) return;
    for (final key in box.keys.toList()) {
      final raw = box.get(key);
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw)..['_nextAttemptAt'] = null;
      await box.put(key, data);
    }
    _retryDelayMinutes = 1;
    await flushQueue();
  }

  /// Flush queued events sequentially to Firestore.
  static Future<void> flushQueue() async {
    if (_box == null || _box!.isEmpty || _isSyncing) {
      return;
    }
    if (!await _verifyReachability()) return;
    _isSyncing = true;

    try {
      final keys = _box!.keys.toList()
        ..sort((left, right) {
          final leftData = _box!.get(left);
          final rightData = _box!.get(right);
          final leftTime = leftData is Map
              ? leftData['timestamp'] as int? ?? 0
              : 0;
          final rightTime = rightData is Map
              ? rightData['timestamp'] as int? ?? 0
              : 0;
          return leftTime.compareTo(rightTime);
        });
      bool anyFailed = false;

      for (final key in keys) {
        final raw = _box!.get(key);
        if (raw is Map) {
          final data = Map<String, dynamic>.from(raw);
          final queueType = data['_queueType'] as String? ?? 'boarding';
          final nextAttemptAt = DateTime.tryParse(
            data['_nextAttemptAt'] as String? ?? '',
          );
          if (nextAttemptAt != null && nextAttemptAt.isAfter(DateTime.now())) {
            continue;
          }

          try {
            if (queueType == 'boarding') {
              final locationMap = data['location'] is Map
                  ? Map<String, dynamic>.from(data['location'] as Map)
                  : <String, dynamic>{};
              final event = BoardingEvent(
                id: data['id'] ?? '',
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
              await FirebaseService.recordAttendance(event);
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
            } else {
              throw StateError('Unsupported offline queue type: $queueType');
            }

            await _box!.delete(key);
            _updateNotifier();
            AppLogger.info('offline_sync', 'A queued operation synchronized.');
          } catch (error, stackTrace) {
            final failure = AppFailureMapper.from(error);
            final incidentId = AppLogger.error(
              'offline_sync',
              'A queued operation failed to synchronize.',
              error: error,
              stackTrace: stackTrace,
            );
            final attemptCount = (data['_attemptCount'] as int? ?? 0) + 1;
            final delayMinutes = failure.retryable
                ? (1 << (attemptCount - 1).clamp(0, 6)).clamp(
                    1,
                    _maxRetryDelayMinutes,
                  )
                : _maxRetryDelayMinutes;
            data
              ..['_attemptCount'] = attemptCount
              ..['_lastAttemptAt'] = DateTime.now().toUtc().toIso8601String()
              ..['_nextAttemptAt'] = DateTime.now()
                  .add(Duration(minutes: delayMinutes))
                  .toUtc()
                  .toIso8601String()
              ..['_failureCategory'] = failure.category.name
              ..['_incidentId'] = incidentId;
            await _box!.put(key, data);
            anyFailed = true;
            continue;
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
