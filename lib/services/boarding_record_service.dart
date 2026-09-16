import 'package:flutter/foundation.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'package:schoolway/core/diagnostics/app_failure.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/models.dart';
import 'firebase_service.dart';
import 'eta_geofence_service.dart';
import 'offline_queue_service.dart';
import 'school_config_service.dart';
import 'location_service.dart';

class AttendanceLocationException implements Exception {
  const AttendanceLocationException(this.reason);

  final AttendanceLocationFailure reason;
}

enum AttendanceLocationFailure { locationUnavailable, outsideSchoolArea }

/// Persists boarding / alighting scans to Firestore and resolves NFC identity.
class BoardingRecordService {
  static final Map<String, Future<AttendanceRecordResult>> _inFlight = {};
  static final AttendanceScanDeduplicator _scanDeduplicator =
      AttendanceScanDeduplicator();

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

  @visibleForTesting
  static bool requiresSchoolArea({
    required TripDirection direction,
    required String eventType,
  }) {
    return (direction == TripDirection.toSchool &&
            isAlightingEventType(eventType)) ||
        (direction == TripDirection.fromSchool &&
            isBoardingEventType(eventType));
  }

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

  static int activeStudentCount(Iterable<Student> students) {
    return students
        .where((student) => student.status.toLowerCase() == 'active')
        .length;
  }

  static Student? findStudentInRosterByNfc(
    String rawNfc,
    Iterable<Student> students,
  ) {
    final normalized = normalizeNfcKey(rawNfc);
    for (final student in students) {
      if (nfcIdsMatch(student.nfcCardId, normalized)) return student;
    }
    return null;
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
    final rosterMatch = findStudentInRosterByNfc(
      rawNfc,
      snapshot.docs.map(Student.fromFirestore),
    );
    if (rosterMatch != null) return rosterMatch;
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
    String? lastKnownEventType,
    int maxAttempts = 5,
  }) {
    final key = '${session.id}:${student.id}';
    final duplicate = _scanDeduplicator.findDuplicate(
      sessionId: session.id,
      studentId: student.id,
      now: DateTime.now(),
    );
    if (duplicate != null) {
      return SynchronousFuture(AttendanceRecordResult.duplicate(duplicate));
    }
    final active = _inFlight[key];
    if (active != null) return active;
    final operation = _recordBoardingForStudent(
      student: student,
      session: session,
      driverUid: driverUid,
      lastKnownEventType: lastKnownEventType,
      maxAttempts: maxAttempts,
    );
    _inFlight[key] = operation;
    operation.then<void>(
      (result) {
        _scanDeduplicator.remember(
          sessionId: session.id,
          studentId: student.id,
          event: result.event,
          recordedAt: DateTime.now(),
        );
        _inFlight.remove(key);
      },
      onError: (Object ignoredError, StackTrace ignoredStackTrace) =>
          _inFlight.remove(key),
    );
    return operation;
  }

  static Future<AttendanceRecordResult> _recordBoardingForStudent({
    required Student student,
    required RouteSession session,
    required String driverUid,
    required String? lastKnownEventType,
    required int maxAttempts,
  }) async {
    Object? lastError;
    final eventId = swFirestore.collection('boarding_events').doc().id;
    var resolvedLastEventType = lastKnownEventType;
    if (shouldQueueImmediately(OfflineQueueService.isOnlineNotifier.value)) {
      final eventType = nextEventType(resolvedLastEventType);
      final location = await _resolveBoardingLocation();
      await _validateSchoolAttendanceLocation(
        eventType: eventType,
        session: session,
        location: location,
      );
      return _queueBoardingEvent(
        eventId: eventId,
        student: student,
        session: session,
        driverUid: driverUid,
        eventType: eventType,
        location: location,
      );
    }
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (kIsWeb && attempt > 1) {
          await Future<void>.delayed(
            Duration(milliseconds: 500 * attempt * attempt),
          );
        }

        // The active NFC tab already streams the last event for this student.
        // The callable remains the authority and calculates the final type, so
        // do not add a network read before every card tap.
        final eventType = nextEventType(resolvedLastEventType);

        final location = await _resolveBoardingLocation();
        await _validateSchoolAttendanceLocation(
          eventType: eventType,
          session: session,
          location: location,
        );

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
        final recorded = await FirebaseService.recordAttendance(event);

        if (kIsWeb) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }

        return AttendanceRecordResult.synced(recorded);
      } catch (e) {
        lastError = e;
        if (attempt < maxAttempts && isFirestoreWebSyncError(e)) continue;

        if (!shouldQueueFailure(e)) rethrow;

        // Queue only transient failures. Permission and validation failures
        // must remain visible to the driver.
        try {
          final location = await _resolveBoardingLocation();
          final eventType = nextEventType(resolvedLastEventType);
          return await _queueBoardingEvent(
            eventId: eventId,
            student: student,
            session: session,
            driverUid: driverUid,
            eventType: eventType,
            location: location,
          );
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

  @visibleForTesting
  static bool shouldQueueImmediately(bool? isOnline) => isOnline == false;

  static Future<AttendanceRecordResult> _queueBoardingEvent({
    required String eventId,
    required Student student,
    required RouteSession session,
    required String driverUid,
    required String eventType,
    required EventLocation location,
  }) async {
    final timestamp = DateTime.now();
    final queuedEvent = BoardingEvent(
      id: eventId,
      studentId: student.id,
      busId: session.busId,
      driverUid: driverUid,
      sessionId: session.id,
      eventType: eventType,
      location: location,
      timestamp: timestamp,
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
      'timestamp': timestamp.millisecondsSinceEpoch,
      'nfcCardId': student.nfcCardId.isNotEmpty ? student.nfcCardId : null,
      'isManual': false,
    });
    return AttendanceRecordResult.queued(queuedEvent);
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
    await _validateSchoolAttendanceLocation(
      eventType: eventType,
      session: session,
      location: location,
    );
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
      final recorded = await FirebaseService.recordAttendance(event);
      return AttendanceRecordResult.synced(recorded);
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

  @visibleForTesting
  static bool isRecentCachedLocation({
    required DateTime timestamp,
    required DateTime now,
  }) {
    return now.difference(timestamp).abs() <= const Duration(seconds: 60);
  }

  @visibleForTesting
  static bool isAcceptableAttendancePosition(Position position, DateTime now) {
    return isRecentCachedLocation(timestamp: position.timestamp, now: now) &&
        position.accuracy.isFinite &&
        position.accuracy >= 0 &&
        position.accuracy <= 100;
  }

  @visibleForTesting
  static Future<EventLocation> resolveBoardingLocationForTesting() =>
      _resolveBoardingLocation();

  static Future<EventLocation> _resolveBoardingLocation() async {
    final now = DateTime.now();
    if (LocationService.isSimulated) {
      final simPos = LocationService.recentPosition(
        now: now,
        maxAge: const Duration(seconds: 60),
      );
      if (simPos != null && isAcceptableAttendancePosition(simPos, now)) {
        return EventLocation(
          name: 'Simulated GPS',
          latitude: simPos.latitude,
          longitude: simPos.longitude,
          accuracy: simPos.accuracy,
          capturedAt: now,
        );
      }
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      LocationService.rememberPosition(pos);
      if (!isAcceptableAttendancePosition(pos, now)) {
        throw const AttendanceLocationException(
          AttendanceLocationFailure.locationUnavailable,
        );
      }
      return EventLocation(
        name: 'GPS',
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        capturedAt: pos.timestamp,
      );
    } catch (_) {
      try {
        final position =
            LocationService.recentPosition(
              now: now,
              maxAge: const Duration(seconds: 60),
            ) ??
            await Geolocator.getLastKnownPosition();
        if (position != null && isAcceptableAttendancePosition(position, now)) {
          return EventLocation(
            name: 'Cached GPS',
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
            capturedAt: position.timestamp,
          );
        }
      } catch (_) {
        // Fall through to throw below.
      }
      throw const AttendanceLocationException(
        AttendanceLocationFailure.locationUnavailable,
      );
    }
  }

  static Future<void> _validateSchoolAttendanceLocation({
    required String eventType,
    required RouteSession session,
    required EventLocation location,
  }) async {
    final isSchoolEvent = requiresSchoolArea(
      direction: session.tripDirection,
      eventType: eventType,
    );
    if (!isSchoolEvent) return;

    final SchoolGeofenceConfig config;
    try {
      config = await SchoolConfigService.getGeofenceConfig();
    } catch (_) {
      throw const AttendanceLocationException(
        AttendanceLocationFailure.locationUnavailable,
      );
    }
    final center = config.center;
    if (center == null) return;
    if (!location.hasValidCoordinates) {
      throw const AttendanceLocationException(
        AttendanceLocationFailure.locationUnavailable,
      );
    }
    final inside = EtaGeofenceService.checkInGeofence(
      currentLocation: LatLng(location.latitude, location.longitude),
      stopLocation: center,
      radiusMeters: config.schoolRadiusMeters,
    );
    if (!inside) {
      throw const AttendanceLocationException(
        AttendanceLocationFailure.outsideSchoolArea,
      );
    }
  }
}

enum AttendanceRecordStatus { synced, queued, duplicate }

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

  factory AttendanceRecordResult.duplicate(BoardingEvent event) =>
      AttendanceRecordResult(
        event: event,
        status: AttendanceRecordStatus.duplicate,
      );

  final BoardingEvent event;
  final AttendanceRecordStatus status;

  bool get isSynced => status == AttendanceRecordStatus.synced;

  bool get isQueued => status == AttendanceRecordStatus.queued;

  bool get isDuplicate => status == AttendanceRecordStatus.duplicate;
}

class TripAttendanceStats {
  const TripAttendanceStats({
    required this.boardedStudentCount,
    required this.currentOnBoardCount,
    required this.alightedStudentCount,
    required this.totalScans,
    required this.lastScanAt,
  });

  factory TripAttendanceStats.fromEvents(Iterable<BoardingEvent> events) {
    final byId = <String, BoardingEvent>{};
    for (final event in events) {
      final key = event.id.isEmpty
          ? '${event.studentId}:${event.timestamp.microsecondsSinceEpoch}:${event.eventType}'
          : event.id;
      final existing = byId[key];
      if (existing == null || event.timestamp.isAfter(existing.timestamp)) {
        byId[key] = event;
      }
    }

    final ordered = byId.values.toList()
      ..sort((first, second) => first.timestamp.compareTo(second.timestamp));
    final boardedStudents = <String>{};
    final latestByStudent = <String, BoardingEvent>{};
    for (final event in ordered) {
      if (BoardingRecordService.isBoardingEventType(event.eventType)) {
        boardedStudents.add(event.studentId);
      }
      latestByStudent[event.studentId] = event;
    }
    final currentOnBoardCount = latestByStudent.values
        .where(
          (event) => BoardingRecordService.isBoardingEventType(event.eventType),
        )
        .length;
    final alightedStudentCount = latestByStudent.values
        .where(
          (event) =>
              BoardingRecordService.isAlightingEventType(event.eventType),
        )
        .length;

    return TripAttendanceStats(
      boardedStudentCount: boardedStudents.length,
      currentOnBoardCount: currentOnBoardCount,
      alightedStudentCount: alightedStudentCount,
      totalScans: ordered.length,
      lastScanAt: ordered.isEmpty ? null : ordered.last.timestamp,
    );
  }

  final int boardedStudentCount;
  final int currentOnBoardCount;
  final int alightedStudentCount;
  final int totalScans;
  final DateTime? lastScanAt;

  int progressCountFor(TripDirection direction) {
    return direction == TripDirection.toSchool
        ? alightedStudentCount
        : currentOnBoardCount;
  }
}

/// Rejects accidental repeat reads of the same card after a completed scan.
///
/// The in-flight guard above coalesces concurrent callbacks. This guard covers
/// the separate case where NFC hardware reports the same card again just after
/// the first write completes, which must not toggle a board event to alight.
class AttendanceScanDeduplicator {
  AttendanceScanDeduplicator({
    this.duplicateWindow = const Duration(seconds: 5),
  });

  final Duration duplicateWindow;
  final Map<String, _RecentAttendanceScan> _recentScans = {};

  BoardingEvent? findDuplicate({
    required String sessionId,
    required String studentId,
    required DateTime now,
  }) {
    _removeExpired(now);
    final recent = _recentScans['$sessionId:$studentId'];
    if (recent == null ||
        now.difference(recent.recordedAt) >= duplicateWindow) {
      return null;
    }
    return recent.event;
  }

  void remember({
    required String sessionId,
    required String studentId,
    required BoardingEvent event,
    required DateTime recordedAt,
  }) {
    _removeExpired(recordedAt);
    _recentScans['$sessionId:$studentId'] = _RecentAttendanceScan(
      event: event,
      recordedAt: recordedAt,
    );
  }

  void _removeExpired(DateTime now) {
    _recentScans.removeWhere(
      (_, scan) => now.difference(scan.recordedAt) >= duplicateWindow,
    );
  }
}

class _RecentAttendanceScan {
  const _RecentAttendanceScan({required this.event, required this.recordedAt});

  final BoardingEvent event;
  final DateTime recordedAt;
}
