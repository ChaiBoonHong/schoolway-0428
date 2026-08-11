class NotificationPreferences {
  static const categories = <String>[
    'boarding',
    'dropoff',
    'delay',
    'route_change',
    'emergency',
  ];

  final bool notificationsEnabled;
  final bool quietHoursEnabled;
  final int quietStartMinutes;
  final int quietEndMinutes;
  final int? timezoneOffsetMinutes;
  final Map<String, Map<String, bool>> students;
  final Map<String, Map<String, bool>> critical;

  const NotificationPreferences({
    this.notificationsEnabled = true,
    this.quietHoursEnabled = false,
    this.quietStartMinutes = 22 * 60,
    this.quietEndMinutes = 6 * 60,
    this.timezoneOffsetMinutes,
    this.students = const {},
    this.critical = const {},
  });

  factory NotificationPreferences.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const NotificationPreferences();
    final start = data['quietStart'] as Map<String, dynamic>?;
    final end = data['quietEnd'] as Map<String, dynamic>?;
    return NotificationPreferences(
      notificationsEnabled: data['notificationsEnabled'] as bool? ?? true,
      quietHoursEnabled: data['quietHoursEnabled'] as bool? ?? false,
      quietStartMinutes: _minutes(start, 22, 0),
      quietEndMinutes: _minutes(end, 6, 0),
      timezoneOffsetMinutes: data['timezoneOffsetMinutes'] as int?,
      students: _boolMatrix(data['students']),
      critical: _boolMatrix(data['critical']),
    );
  }

  bool receives(String studentId, String category) {
    return notificationsEnabled && (students[studentId]?[category] ?? true);
  }

  bool usesCriticalChannel(String studentId, String category) {
    return receives(studentId, category) &&
        (critical[studentId]?[category] ?? category == 'emergency');
  }

  bool isInQuietHours(DateTime now) {
    if (!quietHoursEnabled) return false;
    final local = timezoneOffsetMinutes == null
        ? now
        : now.toUtc().add(Duration(minutes: timezoneOffsetMinutes!));
    final current = local.hour * 60 + local.minute;
    if (quietStartMinutes < quietEndMinutes) {
      return current >= quietStartMinutes && current < quietEndMinutes;
    }
    return current >= quietStartMinutes || current < quietEndMinutes;
  }

  Map<String, dynamic> toMap() => {
    'notificationsEnabled': notificationsEnabled,
    'quietHoursEnabled': quietHoursEnabled,
    'quietStart': {
      'hour': quietStartMinutes ~/ 60,
      'minute': quietStartMinutes % 60,
    },
    'quietEnd': {'hour': quietEndMinutes ~/ 60, 'minute': quietEndMinutes % 60},
    'timezoneOffsetMinutes': timezoneOffsetMinutes,
    'students': students,
    'critical': critical,
  };

  static int _minutes(Map<String, dynamic>? value, int hour, int minute) {
    return ((value?['hour'] as num?)?.toInt() ?? hour) * 60 +
        ((value?['minute'] as num?)?.toInt() ?? minute);
  }

  static Map<String, Map<String, bool>> _boolMatrix(dynamic value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.value is Map)
          entry.key.toString(): {
            for (final setting in (entry.value as Map).entries)
              setting.key.toString(): setting.value as bool? ?? true,
          },
    };
  }
}
