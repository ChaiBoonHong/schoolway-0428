part of '../admin_home.dart';

class AdminReportsTab extends StatelessWidget {
  const AdminReportsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final reportTypes = [
      {
        'title': 'Route History',
        'description':
            'Visualize past routes taken by buses and replay trips',
        'icon': Icons.history,
        'color': Colors.orange,
        'type': 'route_history',
      },
      {
        'title': 'Daily Attendance Report',
        'description':
            'Class rosters with board, drop off, or absent; tap for scan times',
        'icon': Icons.today,
        'color': const Color(0xFF0077B6),
        'type': 'daily',
      },
      {
        'title': 'Bus Activity',
        'description':
            'Board and drop off NFC counts per bus over the last 7 days',
        'icon': Icons.directions_bus_filled,
        'color': const Color(0xFF00B4D8),
        'type': 'bus_activity',
      },
      {
        'title': 'Driver Activity',
        'description':
            'NFC scans attributed to each driver in the last 7 days',
        'icon': Icons.badge,
        'color': Colors.green,
        'type': 'driver_activity',
      },
      {
        'title': 'Emergency Alert History',
        'description':
            'Recent driver emergency alerts with time and resolution status',
        'icon': Icons.emergency_outlined,
        'color': Colors.red,
        'type': 'emergency_history',
      },
      {
        'title': 'Attendance Corrections',
        'description':
            'Manually fix boarding records or driver scanning mistakes',
        'icon': Icons.how_to_reg,
        'color': Colors.deepOrange,
        'type': 'attendance_corrections',
      },
      {
        'title': 'Daily Exceptions & Audit Logs',
        'description':
            'Route exception anomalies, manual overrides, and searchable operational logs',
        'icon': Icons.rule_folder_sharp,
        'color': Colors.purple,
        'type': 'exceptions_audit',
      },
    ];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reports & Analytics',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF03045E),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Operational reports for attendance, buses, and safety',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              color: Color(0xFF0077B6),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Calculate aspect ratio to fill available space
                return GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  physics: const BouncingScrollPhysics(),
                  shrinkWrap: false,
                  childAspectRatio: 1.25,
                  children: reportTypes.map((report) {

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (report['type'] == 'route_history') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminRouteHistoryScreen(),
                          ),
                        );
                      } else if (report['type'] == 'attendance_corrections') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AttendanceCorrectionScreen(),
                          ),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReportsScreen(
                              reportType: report['type']! as String,
                            ),
                          ),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF00B4D8).withValues(alpha: 0.3),
                        ),
                      ),
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          color: Color(0xFF03045E),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: (report['color']! as Color).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    report['icon']! as IconData,
                                    color: report['color']! as Color,
                                    size: 32,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  report['title']! as String,
                                  style: const TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF03045E),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  report['description']! as String,
                                  style: const TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 13,
                                    color: Color(0xFF0077B6),
                                    height: 1.4,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Icon(
                                  Icons.arrow_forward,
                                  size: 20,
                                  color: report['color']! as Color,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Helper Widget for Stat Cards

