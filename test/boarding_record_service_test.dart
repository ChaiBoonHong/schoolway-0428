import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/boarding_record_service.dart';
import 'package:schoolway/services/location_service.dart';

void main() {
  tearDown(LocationService.clearRememberedPosition);

  test('school area is required for direction-specific school scans', () {
    expect(
      BoardingRecordService.requiresSchoolArea(
        direction: TripDirection.toSchool,
        eventType: 'alight',
      ),
      isTrue,
    );
    expect(
      BoardingRecordService.requiresSchoolArea(
        direction: TripDirection.fromSchool,
        eventType: 'board',
      ),
      isTrue,
    );
    expect(
      BoardingRecordService.requiresSchoolArea(
        direction: TripDirection.toSchool,
        eventType: 'board',
      ),
      isFalse,
    );
    expect(
      BoardingRecordService.requiresSchoolArea(
        direction: TripDirection.fromSchool,
        eventType: 'alight',
      ),
      isFalse,
    );
  });

  test('attendance action alternates from the latest event', () {
    expect(BoardingRecordService.nextEventType(null), 'board');
    expect(BoardingRecordService.nextEventType('alight'), 'board');
    expect(BoardingRecordService.nextEventType('board'), 'alight');
    expect(BoardingRecordService.nextEventType('Boarded'), 'alight');
  });

  test('offline NFC identity resolves from the cached bus roster', () {
    final student = Student(
      id: 'student-1',
      studentId: 'S001',
      firstName: 'Ali',
      lastName: 'Tan',
      nfcCardId: '04:A1-B2 C3',
      parentAuthUids: const ['parent-1'],
      assignedBusId: 'bus-1',
      status: 'Active',
      createdAt: DateTime.utc(2026, 9, 10),
    );

    expect(
      BoardingRecordService.findStudentInRosterByNfc('04a1b2c3', [student]),
      same(student),
    );
    expect(
      BoardingRecordService.findStudentInRosterByNfc('different', [student]),
      isNull,
    );
  });

  test('manual reasons require a valid preset and Other details', () {
    expect(
      BoardingRecordService.manualReasonNote('Card forgotten', ''),
      'Card forgotten',
    );
    expect(
      BoardingRecordService.manualReasonNote('Other', 'Battery issue'),
      'Other: Battery issue',
    );
    expect(
      () => BoardingRecordService.manualReasonNote('Other', ' '),
      throwsArgumentError,
    );
    expect(
      () => BoardingRecordService.manualReasonNote('Unknown', ''),
      throwsArgumentError,
    );
  });

  test('only transient attendance failures are queued', () {
    expect(
      BoardingRecordService.shouldQueueFailure(
        FirebaseException(plugin: 'firestore', code: 'unavailable'),
      ),
      isTrue,
    );
    expect(
      BoardingRecordService.shouldQueueFailure(TimeoutException('late')),
      isTrue,
    );
    expect(
      BoardingRecordService.shouldQueueFailure(
        FirebaseException(plugin: 'firestore', code: 'permission-denied'),
      ),
      isFalse,
    );
    expect(
      BoardingRecordService.shouldQueueFailure(ArgumentError('invalid')),
      isFalse,
    );
  });

  test('confirmed offline connectivity bypasses Firestore writes', () {
    expect(BoardingRecordService.shouldQueueImmediately(false), isTrue);
    expect(BoardingRecordService.shouldQueueImmediately(true), isFalse);
    expect(BoardingRecordService.shouldQueueImmediately(null), isFalse);
  });

  test('offline attendance accepts only a recent cached location', () {
    final now = DateTime.utc(2026, 9, 10, 8);
    expect(
      BoardingRecordService.isRecentCachedLocation(
        timestamp: now.subtract(const Duration(seconds: 60)),
        now: now,
      ),
      isTrue,
    );
    expect(
      BoardingRecordService.isRecentCachedLocation(
        timestamp: now.subtract(const Duration(seconds: 61)),
        now: now,
      ),
      isFalse,
    );
  });

  test('driver GPS cache remains available during an offline scan', () {
    final capturedAt = DateTime.utc(2026, 9, 10, 8);
    final position = Position(
      longitude: 101.7,
      latitude: 3.1,
      timestamp: capturedAt,
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    LocationService.rememberPosition(position);

    expect(
      LocationService.recentPosition(
        now: capturedAt.add(const Duration(minutes: 10)),
      ),
      same(position),
    );
    expect(
      LocationService.recentPosition(
        now: capturedAt.add(const Duration(minutes: 16)),
      ),
      isNull,
    );
  });

  test(
    'sequential reads of the same card are ignored within the duplicate window',
    () {
      final guard = AttendanceScanDeduplicator(
        duplicateWindow: const Duration(seconds: 5),
      );
      final recordedAt = DateTime.utc(2026, 8, 29, 10);
      final event = BoardingEvent(
        id: 'event-1',
        studentId: 'student-1',
        busId: 'bus-1',
        driverUid: 'driver-1',
        sessionId: 'session-1',
        eventType: 'board',
        location: EventLocation(name: 'GPS', latitude: 3.1, longitude: 101.7),
        timestamp: recordedAt,
        synced: true,
      );

      guard.remember(
        sessionId: 'session-1',
        studentId: 'student-1',
        event: event,
        recordedAt: recordedAt,
      );

      expect(
        guard.findDuplicate(
          sessionId: 'session-1',
          studentId: 'student-1',
          now: recordedAt.add(const Duration(seconds: 4)),
        ),
        same(event),
      );
      expect(
        guard.findDuplicate(
          sessionId: 'session-1',
          studentId: 'student-2',
          now: recordedAt.add(const Duration(seconds: 4)),
        ),
        isNull,
      );
      expect(
        guard.findDuplicate(
          sessionId: 'session-1',
          studentId: 'student-1',
          now: recordedAt.add(const Duration(seconds: 5)),
        ),
        isNull,
      );
    },
  );

  test('trip stats use each student latest event and include queued scans', () {
    final startedAt = DateTime.utc(2026, 9, 10, 8);
    BoardingEvent event({
      required String id,
      required String studentId,
      required String type,
      required int minute,
      bool synced = true,
    }) {
      return BoardingEvent(
        id: id,
        studentId: studentId,
        busId: 'bus-1',
        driverUid: 'driver-1',
        sessionId: 'session-1',
        eventType: type,
        location: EventLocation(name: 'GPS', latitude: 3.1, longitude: 101.7),
        timestamp: startedAt.add(Duration(minutes: minute)),
        synced: synced,
      );
    }

    final stats = TripAttendanceStats.fromEvents([
      event(id: '1', studentId: 'a', type: 'board', minute: 1),
      event(id: '2', studentId: 'a', type: 'alight', minute: 3),
      event(id: '3', studentId: 'b', type: 'board', minute: 2),
      event(id: '4', studentId: 'c', type: 'board', minute: 4, synced: false),
      event(id: '4', studentId: 'c', type: 'board', minute: 4),
    ]);

    expect(stats.boardedStudentCount, 3);
    expect(stats.currentOnBoardCount, 2);
    expect(stats.totalScans, 4);
    expect(stats.lastScanAt, startedAt.add(const Duration(minutes: 4)));
  });
}
