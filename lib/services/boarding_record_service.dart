import 'package:flutter/foundation.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../models/models.dart';
import 'firebase_service.dart';
import 'offline_queue_service.dart';

/// Persists boarding / alighting scans to Firestore and resolves NFC identity.
class BoardingRecordService {
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
  static Future<String> recordBoardingForStudent({
    required Student student,
    required RouteSession session,
    required String driverUid,
    int maxAttempts = 5,
  }) async {
    Object? lastError;
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
        );
        final eventType = nextEventType(last?.eventType);

        final location = await _resolveBoardingLocation();

        if (kIsWeb) {
          await swFirestore.waitForPendingWrites();
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }

        final event = BoardingEvent(
          id: '',
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
        final eventId = await FirebaseService.createBoardingEvent(event);

        if (kIsWeb) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }

        return eventId;
      } catch (e) {
        lastError = e;
        if (attempt < maxAttempts && isFirestoreWebSyncError(e)) continue;

        // Fallback to offline queueing if network error occurs
        try {
          final location = await _resolveBoardingLocation();
          final last = await FirebaseService.getLastEventForStudentInSession(
            student.id,
            session.id,
          );
          final eventType = nextEventType(last?.eventType);

          await OfflineQueueService.enqueueEvent({
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
          return 'offline_queued_${DateTime.now().millisecondsSinceEpoch}';
        } catch (_) {}

        rethrow;
      }
    }
    throw lastError!;
  }

  /// Records the next attendance event with a required manual fallback reason.
  static Future<String> recordManualBoardingForStudent({
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
      );
      eventType = nextEventType(last?.eventType);
    } catch (_) {
      // Use the latest event already streamed to the driver while offline.
    }
    final location = await _resolveBoardingLocation();
    final event = BoardingEvent(
      id: '',
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
      final id = await FirebaseService.createBoardingEvent(event);
      return id;
    } catch (e) {
      await OfflineQueueService.enqueueEvent({
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
      return 'offline_queued_${DateTime.now().millisecondsSinceEpoch}';
    }
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
