import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/fleet_bus_colors.dart';
import 'package:schoolway/core/fleet_bus_position.dart';
import 'package:schoolway/core/widgets/osm_map_attribution.dart';
import 'package:schoolway/core/widgets/fleet_bus_marker.dart';
import 'package:schoolway/core/widgets/osm_map_tile_layer.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/features/admin/bus_management_screen.dart';
import 'package:schoolway/features/admin/emergency_alerts_screen.dart';
import 'package:schoolway/features/admin/reports_screen.dart';
import 'package:schoolway/features/admin/route_planner_screen.dart';
import 'package:schoolway/features/admin/student_management_screen.dart';
import 'package:schoolway/features/admin/user_management_screen.dart';
import 'package:schoolway/features/admin/csv_importer_screen.dart';
import 'package:schoolway/features/parent/notifications_inbox_screen.dart';
import 'package:schoolway/features/shell/shared_profile_tab.dart';

part 'tabs/live_fleet_tab.dart';
part 'tabs/rosters_tab.dart';
part 'tabs/reports_tab.dart';
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  static const routeName = '/admin';

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _currentTabIndex = 0;

  void _openEmergencyAlerts() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const EmergencyAlertsScreen(),
      ),
    );
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NotificationsInboxScreen(
          onEmergencyTapOpenLiveMap: () {
            if (!mounted) return;
            _openEmergencyAlerts();
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
          'Admin Dashboard',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: Color(0xFF03045E),
          ),
        ),
        actions: [
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
                  final unread = snap.data?.where((n) => !n.read).length ?? 0;
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
          IconButton(
            icon: const Icon(Icons.warning_amber_rounded),
            tooltip: 'Emergency alerts',
            onPressed: _openEmergencyAlerts,
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: const [
          AdminLiveFleetTab(),
          AdminRostersTab(),
          AdminReportsTab(),
          SharedProfileTab(),
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
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on, color: Color(0xFF0077B6)),
            label: 'Live Fleet',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people, color: Color(0xFF0077B6)),
            label: 'Manage',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics, color: Color(0xFF0077B6)),
            label: 'Reports',
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

