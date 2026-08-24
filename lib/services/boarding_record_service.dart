import 'package:flutter/foundation.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'package:schoolway/core/diagnostics/app_failure.dart';
import 'package:geolocator/geolocator.dart';

import '../models/models.dart';
import 'firebase_service.dart';
import 'offline_queue_service.dart';

/// Persists boarding / alighting scans to Firestore and resolves NFC identity.
class BoardingRecordService {
  static final Map<String, Future<AttendanceRecordResult>> _inFlight = {};

  static const manualReasons = <String>[
    'Card forgotten',
    'Card unreadable',
    'NFC unavailable',
    'Admin instruction',
    'Other',
  ];

  static bool isBoardingEventType(String? t) {
    final s = (t ?? '').toLowerCase();
    return s == 'board' || s == 'boarded';
  }

  static bool isDropOffEventType(String? t) {
    final s = (t ?? '').toLowerCase();
    return s == 'alight' ||
        s.startsWith('alight') ||
        s == 'drop off' ||
        s == 'dropped off';
  }

  static bool isAlightingEventType(String? t) => isDropOffEventType(t);

  static String nextEventType(String? lastEventType) =>
      isBoardingEventType(lastEventType) ? 'alight' : 'board';

  static String manualReasonNote(String reason, String? details) {
    if (!manualReasons.contains(reason)) {
      throw ArgumentError.value(reason, 'reason', 'Select a valid reason');
    }
    final extra = details?.trim() ?? '';
    if (reason == 'Other' && extra.isEmpty) {
      throw ArgumentError('Details are required for Other');
    }
    return extra.isEmpty ? reason : '$reason: $extra';
  }

  static String normalizeNfcKey(String s) {
    return s.trim().toLowerCase().replaceAll(RegExp(r'[\s:-]'), '');
  }

  static bool nfcIdsMatch(String stored, String scannedNorm) {
    if (stored.isEmpty || scannedNorm.isEmpty) return false;
    final sn = normalizeNfcKey(stored);
    if (sn == scannedNorm) return true;
    if (sn.length >= 8 && scannedNorm.length >= 8) {
      if (sn.contains(scannedNorm) || scannedNorm.contains(sn)) return true;
    }
    return false;
  }

  /// Find a student on [busId] whose stored [Student.nfcCardId] matches the scan.
  static Future<Student?> findStudentOnBusByNfc(
    String rawNfc,
    String busId,
  ) async {
    final snapshot = await swFirestore
        .collection('students')
        .where('assignedBusId', isEqualTo: busId)
        .get();
    final norm = normalizeNfcKey(rawNfc);
    for (final doc in snapshot.docs) {
      final s = Student.fromFirestore(doc);
      if (nfcIdsMatch(s.nfcCardId, norm)) return s;
    }
    final byExact = await FirebaseService.getStudentByNfcCard(rawNfc.trim());
    if (byExact != null && byExact.assignedBusId == busId) return byExact;
    return null;
  }

  /// Writes the next board or alight event for [student] in [session].
  /// Automatically retries on Firestore web SDK sync errors with exponential
  /// back-off, giving the internal watch pipeline time to recover.
  static Future<AttendanceRecordResult> recordBoardingForStudent({
    required Student student,
    required RouteSession session,
    required String driverUid,
    int maxAttempts = 5,
  }) {
    final key = '${session.id}:${student.id}';
    final active = _inFlight[key];
    if (active != null) return active;
    final operation = _recordBoardingForStudent(
      student: student,
      session: session,
      driverUid: driverUid,
      maxAttempts: maxAttempts,
    );
    _inFlight[key] = operation;
    operation.then<void>(
      (_) => _inFlight.remove(key),
      onError: (Object ignoredError, StackTrace ignoredStackTrace) =>
          _inFlight.remove(key),
    );
    return operation;
  }

  static Future<AttendanceRecordResult> _recordBoardingForStudent({
    required Student student,
    required RouteSession session,
    required String driverUid,
    required int maxAttempts,
  }) async {
    Object? lastError;
    final eventId = swFirestore.collection('boarding_events').doc().id;
    String? lastKnownEventType;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (kIsWeb && attempt > 1) {
          await Future<void>.delayed(
            Duration(milliseconds: 500 * attempt * attempt),
          );
        }

        final last = await FirebaseService.getLastEventForStudentInSession(
          student.id,
          session.id,
          driverUid: driverUid,
        );
        final eventType = nextEventType(last?.eventType);
        lastKnownEventType = last?.eventType;

        final location = await _resolveBoardingLocation();

        if (kIsWeb) {
          await swFirestore.waitForPendingWrites();
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }

        final event = BoardingEvent(
          id: eventId,
          studentId: student.id,
          busId: session.busId,
          driverUid: driverUid,
          sessionId: session.id,
          eventType: eventType,
          location: location,
          timestamp: DateTime.now(),
          nfcCardId: student.nfcCardId.isNotEmpty ? student.nfcCardId : null,
          synced: true,
        );
        await FirebaseService.createBoardingEvent(event);

        if (kIsWeb) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }

        return AttendanceRecordResult.synced(event);
      } catch (e) {
        lastError = e;
        if (attempt < maxAttempts && isFirestoreWebSyncError(e)) continue;

        if (!shouldQueueFailure(e)) rethrow;

        // Queue only transient failures. Permission and validation failures
        // must remain visible to the driver.
        try {
          final location = await _resolveBoardingLocation();
          final eventType = nextEventType(lastKnownEventType);

          final queuedEvent = BoardingEvent(
            id: eventId,
            studentId: student.id,
            busId: session.busId,
            driverUid: driverUid,
            sessionId: session.id,
            eventType: eventType,
            location: location,
            timestamp: DateTime.now(),
            nfcCardId: student.nfcCardId.isNotEmpty ? student.nfcCardId : null,
            synced: false,
          );
          await OfflineQueueService.enqueueEvent({
            'id': eventId,
            'studentId': student.id,
            'busId': session.busId,
            'driverUid': driverUid,
            'sessionId': session.id,
            'eventType': eventType,
            'location': location.toMap(),
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'nfcCardId': student.nfcCardId.isNotEmpty
                ? student.nfcCardId
                : null,
            'isManual': false,
          });
          return AttendanceRecordResult.queued(queuedEvent);
        } catch (error, stackTrace) {
          AppLogger.warning(
            'data',
            'Malformed or unavailable optional data was ignored.',
            error: error,
            stackTrace: stackTrace,
          );
        }

        rethrow;
      }
    }
    throw lastError!;
  }

  /// Records the next attendance event with a required manual fallback reason.
  static Future<AttendanceRecordResult> recordManualBoardingForStudent({
    required Student student,
    required RouteSession session,
    required String driverUid,
    required String reason,
    String? details,
    String? lastKnownEventType,
  }) {
    final key = '${session.id}:${student.id}';
    final active = _inFlight[key];
    if (active != null) return active;
    final operation = _recordManualBoardingForStudent(
      student: student,
      session: session,
      driverUid: driverUid,
      reason: reason,
      details: details,
      lastKnownEventType: lastKnownEventType,
    );
    _inFlight[key] = operation;
    operation.then<void>(
      (_) => _inFlight.remove(key),
      onError: (Object ignoredError, StackTrace ignoredStackTrace) =>
          _inFlight.remove(key),
    );
    return operation;
  }

  static Future<AttendanceRecordResult> _recordManualBoardingForStudent({
    required Student student,
    required RouteSession session,
    required String driverUid,
    required String reason,
    String? details,
    String? lastKnownEventType,
  }) async {
    final note = manualReasonNote(reason, details);
    var eventType = nextEventType(lastKnownEventType);
    try {
      final last = await FirebaseService.getLastEventForStudentInSession(
        student.id,
        session.id,
        driverUid: driverUid,
      );
      eventType = nextEventType(last?.eventType);
    } catch (_) {
      // Use the latest event already streamed to the driver while offline.
    }
    final location = await _resolveBoardingLocation();
    final eventId = swFirestore.collection('boarding_events').doc().id;
    final event = BoardingEvent(
      id: eventId,
      studentId: student.id,
      busId: session.busId,
      driverUid: driverUid,
      sessionId: session.id,
      eventType: eventType,
      location: location,
      timestamp: DateTime.now(),
      synced: true,
      isManual: true,
      manualNote: note,
    );
    try {
      await FirebaseService.createBoardingEvent(event);
      return AttendanceRecordResult.synced(event);
    } catch (e) {
      if (!shouldQueueFailure(e)) rethrow;
      await OfflineQueueService.enqueueEvent({
        'id': eventId,
        'studentId': student.id,
        'busId': session.busId,
        'driverUid': driverUid,
        'sessionId': session.id,
        'eventType': eventType,
        'location': location.toMap(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isManual': true,
        'manualNote': note,
      });
      return AttendanceRecordResult.queued(
        BoardingEvent(
          id: event.id,
          studentId: event.studentId,
          busId: event.busId,
          driverUid: event.driverUid,
          sessionId: event.sessionId,
          eventType: event.eventType,
          location: event.location,
          timestamp: event.timestamp,
          nfcCardId: event.nfcCardId,
          synced: false,
          isManual: true,
          manualNote: event.manualNote,
        ),
      );
    }
  }

  @visibleForTesting
  static bool shouldQueueFailure(Object error) {
    if (isFirestoreWebSyncError(error)) return true;
    final failure = AppFailureMapper.from(error);
    return failure.retryable &&
        (failure.category == AppFailureCategory.network ||
            failure.category == AppFailureCategory.timeout ||
            failure.category == AppFailureCategory.unavailable);
  }

  static bool isFirestoreWebSyncError(Object e) {
    final s = e.toString();
    return s.contains('INTERNAL ASSERTION') ||
        s.contains('Unexpected state') ||
        s.contains('WatchChangeAggregator');
  }

  static Future<EventLocation> _resolveBoardingLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 8),
        ),
      );
      return EventLocation(
        name: 'GPS',
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    } catch (_) {
      return EventLocation(name: 'Unknown', latitude: 0, longitude: 0);
    }
  }
}

enum AttendanceRecordStatus { synced, queued }

class AttendanceRecordResult {
  const AttendanceRecordResult({required this.event, required this.status});

  factory AttendanceRecordResult.synced(BoardingEvent event) =>
      AttendanceRecordResult(
        event: event,
        status: AttendanceRecordStatus.synced,
      );

  factory AttendanceRecordResult.queued(BoardingEvent event) =>
      AttendanceRecordResult(
        event: event,
        status: AttendanceRecordStatus.queued,
      );

  final BoardingEvent event;
  final AttendanceRecordStatus status;

  bool get isSynced => status == AttendanceRecordStatus.synced;
}
