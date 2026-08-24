import 'package:schoolway/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:schoolway/features/parent/notifications_inbox_screen.dart';
import 'package:schoolway/features/parent/notification_prefs_screen.dart';
import 'package:schoolway/features/shell/shared_profile_tab.dart';
import 'package:schoolway/features/parent/tabs/children_tab.dart';
import 'package:schoolway/features/parent/tabs/live_map_tab.dart';
import 'package:schoolway/features/parent/tabs/trip_history_tab.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/core/widgets/responsive_role_shell.dart';

class ParentHome extends StatefulWidget {
  const ParentHome({super.key});

  static const routeName = '/parent';

  @override
  State<ParentHome> createState() => _ParentHomeState();
}

class _ParentHomeState extends State<ParentHome> {
  int _currentTabIndex = 0;
  String? _tripHistoryFocusStudentId;

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NotificationsInboxScreen(
          onEmergencyTapOpenLiveMap: () {
            if (!mounted) return;
            setState(() => _currentTabIndex = 0);
          },
          onBoardingTapOpenTripHistory: (studentId) {
            if (!mounted) return;
            setState(() {
              _currentTabIndex = 1;
              _tripHistoryFocusStudentId = studentId;
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveRoleShell(
      title: 'Parent Dashboard',
      selectedIndex: _currentTabIndex,
      onDestinationSelected: (index) =>
          setState(() => _currentTabIndex = index),
      actions: [
        IconButton(
          icon: Icon(Icons.settings_outlined),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => NotificationPrefsScreen()),
            );
          },
          tooltip: AppLocalizations.of(context).notificationPreferences,
        ),
        Builder(
          builder: (context) {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid == null) {
              return IconButton(
                icon: Icon(Icons.notifications_outlined),
                onPressed: _openNotifications,
                tooltip: AppLocalizations.of(context).notifications,
              );
            }
            return StreamBuilder<List<InAppNotification>>(
              stream: FirebaseService.notificationsForAuthUid(uid),
              builder: (context, snap) {
                final unread = snap.data?.where((n) => !n.read).length ?? 0;
                return Badge(
                  isLabelVisible: unread > 0,
                  label: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: TextStyle(fontSize: 10),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.notifications_outlined),
                    onPressed: _openNotifications,
                    tooltip: AppLocalizations.of(context).notifications,
                  ),
                );
              },
            );
          },
        ),
      ],
      destinations: [
        RoleDestination(
          label: AppLocalizations.of(context).liveMap,
          icon: Icons.map_outlined,
          selectedIcon: Icons.map,
        ),
        RoleDestination(
          label: AppLocalizations.of(context).tripHistory,
          icon: Icons.history_outlined,
          selectedIcon: Icons.history,
        ),
        RoleDestination(
          label: AppLocalizations.of(context).children,
          icon: Icons.family_restroom_outlined,
          selectedIcon: Icons.family_restroom,
        ),
      ],
      children: [
        ParentLiveMapTab(),
        ParentTripHistoryTab(focusStudentId: _tripHistoryFocusStudentId),
        ParentChildrenTab(),
        SharedProfileTab(),
      ],
    );
  }
}
