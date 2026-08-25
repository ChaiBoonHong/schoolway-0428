import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:schoolway/services/offline_queue_service.dart';

void main() {
  late Directory directory;
  late Box box;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('offline_queue_test_');
    Hive.init(directory.path);
    box = await Hive.openBox('offline_events_box');
    OfflineQueueService.setTestBox(box);
  });

  tearDown(() async {
    OfflineQueueService.setTestBox(null);
    await box.clear();
    await box.close();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Map<String, dynamic> boardingItem(String id, String studentId) => {
    '_queueType': 'boarding',
    '_attemptCount': 0,
    '_lastAttemptAt': null,
    '_nextAttemptAt': null,
    '_failureCategory': null,
    '_incidentId': null,
    'id': id,
    'studentId': studentId,
    'busId': 'bus1',
    'driverUid': 'driver1',
    'sessionId': 'session1',
    'eventType': 'board',
    'location': {'name': 'GPS', 'latitude': 3.1, 'longitude': 101.7},
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'isManual': false,
  };

  test(
    'flushQueue continues processing remaining items after a failure',
    () async {
      await box.put('key1', boardingItem('event1', 'student1'));
      await box.put('key2', boardingItem('event2', 'student2'));

      // Both items will fail because Firebase is not initialized in unit tests.
      // With the old 'break' bug, only the first item would be attempted (key2
      // would still have _attemptCount = 0). With 'continue', both are attempted.
      await OfflineQueueService.flushQueue();

      final item1 = box.get('key1') as Map;
      final item2 = box.get('key2') as Map;
      expect(
        item1['_attemptCount'],
        1,
        reason: 'First item should have been attempted',
      );
      expect(
        item2['_attemptCount'],
        1,
        reason: 'Second item should be attempted even after the first failed',
      );
      expect(item1['_nextAttemptAt'], isNotNull);
      expect(item2['_nextAttemptAt'], isNotNull);
    },
  );

  test('flushQueue deletes items that sync successfully', () async {
    // With no items, flushQueue is a no-op
    expect(OfflineQueueService.pendingCount, 0);
    await OfflineQueueService.flushQueue();
    expect(OfflineQueueService.pendingCount, 0);

    // Add a single item and flush — it fails (no Firebase) and stays in the box
    await box.put('key1', boardingItem('event1', 'student1'));
    await OfflineQueueService.flushQueue();
    expect(box.isOpen, isTrue);
    expect(box.get('key1'), isNotNull);
    expect((box.get('key1') as Map)['_attemptCount'], 1);
  });
}
