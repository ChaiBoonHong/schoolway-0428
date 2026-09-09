import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/boarding_record_service.dart';

void main() {
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
}
