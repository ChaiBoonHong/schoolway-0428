import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/services/boarding_record_service.dart';

void main() {
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
}
