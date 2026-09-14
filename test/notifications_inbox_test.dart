import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/models/models.dart';

void main() {
  group('Notifications grouping and metadata', () {
    test('groups notifications by date chronologically', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 8, 30);
      final yesterday = DateTime(now.year, now.month, now.day - 1, 14, 15);
      final twoDaysAgo = DateTime(now.year, now.month, now.day - 2, 9, 0);

      final notifications = [
        InAppNotification(
          id: 'n1',
          recipientUid: 'parent-1',
          title: 'Child Boarded',
          body: 'Aisyah boarded Bus 1',
          type: 'boarding',
          createdAt: today,
          read: false,
          studentId: 's1',
        ),
        InAppNotification(
          id: 'n2',
          recipientUid: 'parent-1',
          title: 'Child Alighted',
          body: 'Aisyah reached Kindergarten',
          type: 'dropoff',
          createdAt: today,
          read: true,
          studentId: 's1',
        ),
        InAppNotification(
          id: 'n3',
          recipientUid: 'parent-1',
          title: 'Emergency Alert',
          body: 'Bus stationary on route',
          type: 'emergency',
          createdAt: yesterday,
          read: true,
        ),
        InAppNotification(
          id: 'n4',
          recipientUid: 'parent-1',
          title: 'Welcome to SchoolWay',
          body: 'Your account is ready',
          type: 'general',
          createdAt: twoDaysAgo,
          read: true,
        ),
      ];

      final grouped = <DateTime, List<InAppNotification>>{};
      for (final n in notifications) {
        final dateKey = DateTime(
          n.createdAt.year,
          n.createdAt.month,
          n.createdAt.day,
        );
        grouped.putIfAbsent(dateKey, () => []).add(n);
      }

      expect(grouped.keys.length, 3);
      final todayKey = DateTime(now.year, now.month, now.day);
      final yesterdayKey = DateTime(now.year, now.month, now.day - 1);
      final twoDaysAgoKey = DateTime(now.year, now.month, now.day - 2);

      expect(grouped[todayKey]?.length, 2);
      expect(grouped[yesterdayKey]?.length, 1);
      expect(grouped[twoDaysAgoKey]?.length, 1);
    });

    test('InAppNotification holds notification fields properly', () {
      final now = DateTime.now();
      final notification = InAppNotification(
        id: 'n-test',
        recipientUid: 'parent-123',
        title: 'Boarding Alert',
        body: 'Your child has boarded',
        type: 'boarding',
        createdAt: now,
        read: false,
        studentId: 'std-1',
        location: AlertLocation(latitude: 3.1415, longitude: 101.6869),
      );

      expect(notification.id, 'n-test');
      expect(notification.recipientUid, 'parent-123');
      expect(notification.title, 'Boarding Alert');
      expect(notification.body, 'Your child has boarded');
      expect(notification.type, 'boarding');
      expect(notification.category, 'boarding');
      expect(notification.read, false);
      expect(notification.studentId, 'std-1');
      expect(notification.location?.latitude, closeTo(3.1415, 0.0001));
      expect(notification.location?.longitude, closeTo(101.6869, 0.0001));
    });
  });
}
