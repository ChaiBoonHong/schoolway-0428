import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/models/notification_preferences.dart';

void main() {
  test('missing preferences enable notifications and only emergency is critical', () {
    const preferences = NotificationPreferences();

    expect(preferences.receives('student-1', 'boarding'), isTrue);
    expect(preferences.usesCriticalChannel('student-1', 'boarding'), isFalse);
    expect(preferences.usesCriticalChannel('student-1', 'emergency'), isTrue);
  });

  test('master and per-child switches prevent delivery', () {
    const masterOff = NotificationPreferences(notificationsEnabled: false);
    const childOff = NotificationPreferences(
      students: {
        'student-1': {'boarding': false},
      },
    );

    expect(masterOff.receives('student-1', 'emergency'), isFalse);
    expect(childOff.receives('student-1', 'boarding'), isFalse);
    expect(childOff.receives('student-2', 'boarding'), isTrue);
  });

  test('quiet hours support midnight crossover using saved timezone', () {
    const preferences = NotificationPreferences(
      quietHoursEnabled: true,
      timezoneOffsetMinutes: 480,
    );

    expect(
      preferences.isInQuietHours(DateTime.utc(2026, 1, 1, 15)),
      isTrue,
    ); // 23:00 UTC+8
    expect(
      preferences.isInQuietHours(DateTime.utc(2026, 1, 1, 4)),
      isFalse,
    ); // 12:00 UTC+8
  });
}
