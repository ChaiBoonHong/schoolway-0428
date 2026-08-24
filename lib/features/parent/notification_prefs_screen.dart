import 'package:schoolway/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/services/push_messaging_service.dart';

class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  State<NotificationPrefsScreen> createState() =>
      _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen>
    with WidgetsBindingObserver {
  static const _categoryDetails =
      <String, ({String title, String subtitle, IconData icon})>{
        'boarding': (
          title: 'Boarding',
          subtitle: 'When your child boards the bus',
          icon: Icons.directions_bus_filled_outlined,
        ),
        'dropoff': (
          title: 'Drop-off',
          subtitle: 'When your child leaves the bus',
          icon: Icons.exit_to_app,
        ),
        'delay': (
          title: 'Delay',
          subtitle: 'Route delays and ETA changes',
          icon: Icons.schedule_outlined,
        ),
        'route_change': (
          title: 'Route change',
          subtitle: 'Bus or route reassignment',
          icon: Icons.alt_route,
        ),
        'emergency': (
          title: 'Emergency',
          subtitle: 'Safety alerts from the driver',
          icon: Icons.warning_amber_rounded,
        ),
      };

  bool _loading = true;
  bool _saving = false;
  bool _saveAgain = false;
  bool _notificationsEnabled = true;
  bool _quietHoursEnabled = false;
  bool _systemNotificationsEnabled = true;
  bool _criticalAccess = false;
  TimeOfDay _quietStart = TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = TimeOfDay(hour: 6, minute: 0);
  String? _uid;
  String? _saveMessage;
  List<Student> _children = [];
  final Map<String, Map<String, bool>> _studentPrefs = {};
  final Map<String, Map<String, bool>> _criticalPrefs = {};

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshSystemStatus();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final studentsSnapshot = await FirebaseService.studentsCollection
          .where('parentAuthUids', arrayContains: uid)
          .get();
      final children = studentsSnapshot.docs
          .map(Student.fromFirestore)
          .toList();
      final preferences = await FirebaseService.getNotificationPreferences(
        authUid: uid,
      );

      _children = children;
      _notificationsEnabled = preferences.notificationsEnabled;
      _quietHoursEnabled = preferences.quietHoursEnabled;
      _quietStart = TimeOfDay(
        hour: preferences.quietStartMinutes ~/ 60,
        minute: preferences.quietStartMinutes % 60,
      );
      _quietEnd = TimeOfDay(
        hour: preferences.quietEndMinutes ~/ 60,
        minute: preferences.quietEndMinutes % 60,
      );
      for (final child in children) {
        _studentPrefs[child.id] = {
          for (final category in NotificationPreferences.categories)
            category: preferences.students[child.id]?[category] ?? true,
        };
        _criticalPrefs[child.id] = {
          for (final category in NotificationPreferences.categories)
            category:
                preferences.critical[child.id]?[category] ??
                category == 'emergency',
        };
      }
      await _refreshSystemStatus(notify: false);
    } catch (error) {
      _saveMessage = 'Could not load settings: $error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  NotificationPreferences _currentPreferences() => NotificationPreferences(
    notificationsEnabled: _notificationsEnabled,
    quietHoursEnabled: _quietHoursEnabled,
    quietStartMinutes: _quietStart.hour * 60 + _quietStart.minute,
    quietEndMinutes: _quietEnd.hour * 60 + _quietEnd.minute,
    timezoneOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
    students: {
      for (final entry in _studentPrefs.entries) entry.key: Map.of(entry.value),
    },
    critical: {
      for (final entry in _criticalPrefs.entries)
        entry.key: Map.of(entry.value),
    },
  );

  Future<void> _queueSave() async {
    final uid = _uid;
    if (uid == null) return;
    if (_saving) {
      _saveAgain = true;
      return;
    }
    do {
      _saveAgain = false;
      if (mounted) {
        setState(() {
          _saving = true;
          _saveMessage = 'Saving…';
        });
      }
      try {
        await FirebaseService.saveNotificationPreferences(
          authUid: uid,
          preferences: _currentPreferences(),
        );
        if (mounted) setState(() => _saveMessage = 'Saved');
      } catch (error) {
        if (mounted) setState(() => _saveMessage = 'Save failed: $error');
      }
    } while (_saveAgain);
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _refreshSystemStatus({bool notify = true}) async {
    if (!_isAndroid) return;
    final enabled = await PushMessagingService.areSystemNotificationsEnabled();
    final critical = await PushMessagingService.hasCriticalAlertAccess();
    if (mounted && notify) {
      setState(() {
        _systemNotificationsEnabled = enabled;
        _criticalAccess = critical;
      });
    } else {
      _systemNotificationsEnabled = enabled;
      _criticalAccess = critical;
    }
  }

  Future<void> _requestCriticalAccess() async {
    await PushMessagingService.requestCriticalAlertAccess();
    await _refreshSystemStatus();
  }

  Future<void> _pickTime(bool start) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: start ? _quietStart : _quietEnd,
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (start) {
        _quietStart = selected;
      } else {
        _quietEnd = selected;
      }
    });
    await _queueSave();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).notificationSettings),
        actions: [
          if (_saving)
            Padding(
              padding: EdgeInsets.all(SchoolWayTheme.spacing12),
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_saveMessage == 'Saved')
            Padding(
              padding: EdgeInsets.all(SchoolWayTheme.spacing12),
              child: Icon(Icons.check_circle, color: SchoolWayTheme.success),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(SchoolWayTheme.spacing16),
        children: [
          if (_saveMessage != null && _saveMessage != 'Saved' && !_saving)
            _MessageCard(
              icon: Icons.error_outline,
              message: _saveMessage!,
              color: SchoolWayTheme.danger,
            ),
          if (_isAndroid && !_systemNotificationsEnabled) ...[
            _PermissionCard(
              icon: Icons.notifications_off_outlined,
              title: 'Phone notifications are off',
              body:
                  'Android will block normal and critical alerts until SchoolWay notifications are enabled.',
              actionLabel: 'Open phone settings',
              color: SchoolWayTheme.danger,
              onPressed: PushMessagingService.openSystemNotificationSettings,
            ),
            SizedBox(height: SchoolWayTheme.spacing12),
          ],
          if (_isAndroid && !_criticalAccess) ...[
            _PermissionCard(
              icon: Icons.priority_high_rounded,
              title: 'Critical access is not enabled',
              body:
                  'Allow Notification Policy Access so selected alerts can bypass Do Not Disturb.',
              actionLabel: 'Enable critical alerts',
              color: SchoolWayTheme.warning,
              onPressed: _requestCriticalAccess,
            ),
            SizedBox(height: SchoolWayTheme.spacing12),
          ],
          Card(
            child: SwitchListTile(
              secondary: Icon(Icons.notifications_active_outlined),
              title: Text(
                AppLocalizations.of(context).receiveSchoolwayNotifications,
              ),
              subtitle: Text(
                AppLocalizations.of(context).turnOffToStopAllNewPush,
              ),
              value: _notificationsEnabled,
              onChanged: (value) async {
                if (value) {
                  final granted =
                      await PushMessagingService.requestNotificationPermission();
                  if (!granted || !mounted) return;
                }
                setState(() => _notificationsEnabled = value);
                await _queueSave();
              },
            ),
          ),
          SizedBox(height: SchoolWayTheme.spacing12),
          _MessageCard(
            icon: Icons.info_outline,
            message:
                'Critical delivery may bypass Do Not Disturb, but it can never override notifications disabled in phone settings.',
            color: SchoolWayTheme.primary,
          ),
          SizedBox(height: SchoolWayTheme.spacing24),
          _SectionTitle(title: 'Quiet hours'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.bedtime_outlined),
                  title: Text(AppLocalizations.of(context).muteRoutineAlerts),
                  subtitle: Text(
                    AppLocalizations.of(
                      context,
                    ).emergencyAlertsRemainAvailableDuringQuietHours,
                  ),
                  value: _quietHoursEnabled,
                  onChanged: _notificationsEnabled
                      ? (value) {
                          setState(() => _quietHoursEnabled = value);
                          _queueSave();
                        }
                      : null,
                ),
                if (_quietHoursEnabled) ...[
                  Divider(height: 1),
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          title: Text(AppLocalizations.of(context).start),
                          subtitle: Text(_quietStart.format(context)),
                          onTap: _notificationsEnabled
                              ? () => _pickTime(true)
                              : null,
                        ),
                      ),
                      Expanded(
                        child: ListTile(
                          title: Text(AppLocalizations.of(context).end),
                          subtitle: Text(_quietEnd.format(context)),
                          onTap: _notificationsEnabled
                              ? () => _pickTime(false)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: SchoolWayTheme.spacing24),
          _SectionTitle(title: 'Children'),
          if (_children.isEmpty)
            const _MessageCard(
              icon: Icons.family_restroom,
              message: 'No children are linked to this parent account.',
              color: SchoolWayTheme.muted,
            )
          else
            for (var index = 0; index < _children.length; index++) ...[
              _buildChildCard(_children[index], initiallyExpanded: index == 0),
              if (index != _children.length - 1)
                SizedBox(height: SchoolWayTheme.spacing12),
            ],
          SizedBox(height: SchoolWayTheme.spacing32),
        ],
      ),
    );
  }

  Widget _buildChildCard(Student child, {required bool initiallyExpanded}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(child.fullName),
        subtitle: Text(
          AppLocalizations.of(context).chooseDeliveryForEachCategory,
        ),
        children: [
          Divider(height: 1),
          for (final category in NotificationPreferences.categories)
            _buildCategoryRow(child.id, category),
        ],
      ),
    );
  }

  Widget _buildCategoryRow(String studentId, String category) {
    final details = _categoryDetails[category]!;
    final receives = _studentPrefs[studentId]![category]!;
    final critical = _criticalPrefs[studentId]![category]!;
    final enabled = _notificationsEnabled;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                details.icon,
                color: category == 'emergency'
                    ? SchoolWayTheme.danger
                    : SchoolWayTheme.primary,
              ),
              SizedBox(width: SchoolWayTheme.spacing12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      details.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    SizedBox(height: SchoolWayTheme.spacing4),
                    Text(
                      details.subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(
                value: receives,
                onChanged: enabled
                    ? (value) {
                        setState(
                          () => _studentPrefs[studentId]![category] = value,
                        );
                        _queueSave();
                      }
                    : null,
              ),
            ],
          ),
          SizedBox(height: SchoolWayTheme.spacing4),
          Row(
            children: [
              SizedBox(width: 36),
              Expanded(
                child: Text(AppLocalizations.of(context).criticalDelivery),
              ),
              Switch(
                value: critical,
                onChanged: enabled && receives
                    ? (value) {
                        setState(
                          () => _criticalPrefs[studentId]![category] = value,
                        );
                        _queueSave();
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: SchoolWayTheme.spacing8),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(SchoolWayTheme.spacing16),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      border: Border.all(color: color.withValues(alpha: 0.28)),
      borderRadius: BorderRadius.circular(SchoolWayTheme.radius),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        SizedBox(width: SchoolWayTheme.spacing12),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final Color color;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(SchoolWayTheme.spacing16),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      border: Border.all(color: color.withValues(alpha: 0.35)),
      borderRadius: BorderRadius.circular(SchoolWayTheme.radius),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        SizedBox(width: SchoolWayTheme.spacing12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              SizedBox(height: SchoolWayTheme.spacing4),
              Text(body),
              SizedBox(height: SchoolWayTheme.spacing8),
              TextButton(onPressed: onPressed, child: Text(actionLabel)),
            ],
          ),
        ),
      ],
    ),
  );
}
