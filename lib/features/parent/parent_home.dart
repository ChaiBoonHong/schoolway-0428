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
import 'package:schoolway/core/widgets/fade_indexed_stack.dart';
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
    return Scaffold(
      backgroundColor: const Color(0xFFCAF0F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFCAF0F8),
        elevation: 0,
        foregroundColor: const Color(0xFF03045E),
        title: const Text(
          'Parent Dashboard',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: Color(0xFF03045E),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationPrefsScreen(),
                ),
              );
            },
            tooltip: 'Notification Preferences',
          ),
          Builder(
            builder: (context) {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) {
                return IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: _openNotifications,
                  tooltip: 'Notifications',
                );
              }
              return StreamBuilder<List<InAppNotification>>(
                stream: FirebaseService.notificationsForAuthUid(uid),
                builder: (context, snap) {
                  final unread =
                      snap.data?.where((n) => !n.read).length ?? 0;
                  return Badge(
                    isLabelVisible: unread > 0,
                    label: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(fontSize: 10),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.notifications_outlined),
                      onPressed: _openNotifications,
                      tooltip: 'Notifications',
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: FadeIndexedStack(
        index: _currentTabIndex,
        children: [
          const ParentLiveMapTab(),
          ParentTripHistoryTab(
            focusStudentId: _tripHistoryFocusStudentId,
          ),
          const ParentChildrenTab(),
          const SharedProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFFCAF0F8),
        indicatorColor: const Color(0xFF00B4D8).withValues(alpha: 0.3),
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentTabIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map, color: Color(0xFF0077B6)),
            label: 'Live Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history, color: Color(0xFF0077B6)),
            label: 'Trip History',
          ),
          NavigationDestination(
            icon: Icon(Icons.family_restroom_outlined),
            selectedIcon: Icon(Icons.family_restroom, color: Color(0xFF0077B6)),
            label: 'Children',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: Color(0xFF0077B6)),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

