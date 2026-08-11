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
}
