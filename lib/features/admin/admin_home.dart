import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
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
import 'package:schoolway/features/admin/admin_route_history_screen.dart';
import 'package:schoolway/features/admin/attendance_correction_screen.dart';
import 'package:schoolway/features/parent/notifications_inbox_screen.dart';
import 'package:schoolway/features/shell/shared_profile_tab.dart';
import 'package:schoolway/core/widgets/responsive_role_shell.dart';

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
      MaterialPageRoute<void>(builder: (_) => EmergencyAlertsScreen()),
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
    return ResponsiveRoleShell(
      title: 'SchoolWay Admin',
      selectedIndex: _currentTabIndex,
      onDestinationSelected: (index) =>
          setState(() => _currentTabIndex = index),
      actions: [
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
        StreamBuilder<List<EmergencyAlert>>(
          stream: FirebaseService.getActiveEmergencyAlerts(),
          builder: (context, snap) {
            final active = snap.data?.length ?? 0;
            return Badge(
              isLabelVisible: active > 0,
              backgroundColor: SchoolWayTheme.danger,
              label: Text(
                active > 99 ? '99+' : '$active',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: SchoolWayTheme.surface,
                ),
              ),
              child: IconButton(
                icon: Icon(Icons.warning_amber_rounded),
                onPressed: _openEmergencyAlerts,
                tooltip: active > 0
                    ? 'Emergency alerts ($active active)'
                    : 'Emergency alerts',
              ),
            );
          },
        ),
      ],
      destinations: [
        RoleDestination(
          label: AppLocalizations.of(context).buses,
          icon: Icons.directions_bus_outlined,
          selectedIcon: Icons.directions_bus,
        ),
        RoleDestination(
          label: AppLocalizations.of(context).users,
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
        ),
        RoleDestination(
          label: AppLocalizations.of(context).reports,
          icon: Icons.analytics_outlined,
          selectedIcon: Icons.analytics,
        ),
      ],
      children: [
        AdminLiveFleetTab(),
        AdminRostersTab(),
        AdminReportsTab(),
        SharedProfileTab(),
      ],
    );
  }
}
