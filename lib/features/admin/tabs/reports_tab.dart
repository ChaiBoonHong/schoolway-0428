part of '../admin_home.dart';

class AdminReportsTab extends StatefulWidget {
  const AdminReportsTab({super.key});

  @override
  State<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends State<AdminReportsTab> {
  int _activeBusesCount = 0;
  int _totalCheckedIn = 0;
  List<IncidentReport> _recentIncidents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    try {
      // 1. Active Buses Count
      final sessionsSnap = await swFirestore
          .collection('route_sessions')
          .where('endTime', isNull: true)
          .get();
      _activeBusesCount = sessionsSnap.docs.length;

      // 2. Total Checked-in Students
      int checkedIn = 0;
      for (var doc in sessionsSnap.docs) {
        final eventsSnap = await swFirestore
            .collection('boarding_events')
            .where('sessionId', isEqualTo: doc.id)
            .get();
        final boardCount = eventsSnap.docs
            .where((e) => e['eventType'] == 'board')
            .length;
        final alightCount = eventsSnap.docs
            .where((e) => e['eventType'] == 'alight')
            .length;
        checkedIn += (boardCount - alightCount);
      }
      _totalCheckedIn = checkedIn;

      // 3. Recent Incidents
      final incidentsSnap = await swFirestore
          .collection('incidents')
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();

      _recentIncidents = incidentsSnap.docs
          .map((d) => IncidentReport.fromFirestore(d))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error(
        'reports',
        'Administrator dashboard data failed to load.',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.schoolWayColors;
    final reportTypes = [
      {
        'title': 'Route History',
        'description': 'Visualize past routes taken by buses and replay trips',
        'icon': Icons.history,
        'color': SchoolWayTheme.warning,
        'type': 'route_history',
      },
      {
        'title': 'Daily Attendance Report',
        'description':
            'Class rosters with board, alighted, or absent; tap for scan times',
        'icon': Icons.today,
        'color': SchoolWayTheme.primary,
        'type': 'daily',
      },
      {
        'title': 'Bus Activity',
        'description':
            'Board and alighted NFC counts per bus over the last 7 days',
        'icon': Icons.directions_bus_filled,
        'color': SchoolWayTheme.accent,
        'type': 'bus_activity',
      },
      {
        'title': 'Driver Activity',
        'description': 'NFC scans attributed to each driver in the last 7 days',
        'icon': Icons.badge,
        'color': SchoolWayTheme.success,
        'type': 'driver_activity',
      },
      {
        'title': 'Emergency Alert History',
        'description':
            'Recent driver emergency alerts with time and resolution status',
        'icon': Icons.emergency_outlined,
        'color': SchoolWayTheme.danger,
        'type': 'emergency_history',
      },
      {
        'title': 'Attendance Corrections',
        'description':
            'Manually fix boarding records or driver scanning mistakes',
        'icon': Icons.how_to_reg,
        'color': SchoolWayTheme.warningDark,
        'type': 'attendance_corrections',
      },
      {
        'title': 'Daily Exceptions & Audit Logs',
        'description':
            'Route exception anomalies, manual overrides, and searchable operational logs',
        'icon': Icons.rule_folder_sharp,
        'color': SchoolWayTheme.purple,
        'type': 'exceptions_audit',
      },
    ];

    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        physics: AlwaysScrollableScrollPhysics(),
        children: [
          Text(
            AppLocalizations.of(context).operationalOverview,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colors.headerText,
            ),
          ),
          SizedBox(height: 16),
          _buildMetricsGrid(),
          SizedBox(height: 16),
          _buildPerformanceMetric(),
          SizedBox(height: 24),
          _buildIncidentsSection(),
          SizedBox(height: 24),
          Text(
            AppLocalizations.of(context).reportsAnalytics,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colors.headerText,
            ),
          ),
          SizedBox(height: 8),
          Text(
            AppLocalizations.of(
              context,
            ).operationalReportsForAttendanceBusesAndSafety,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              color: colors.mutedText,
            ),
          ),
          SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth >= 1024
                  ? 4
                  : constraints.maxWidth >= 600
                  ? 3
                  : 2;
              final textScale = MediaQuery.textScalerOf(
                context,
              ).scale(1).clamp(1.0, 2.0);

              return GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 288 * textScale,
                physics: NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                children: reportTypes.map((report) {
                  return AdminReportCard(
                    title: report['title']! as String,
                    description: report['description']! as String,
                    icon: report['icon']! as IconData,
                    color: report['color']! as Color,
                    onTap: () {
                      if (report['type'] == 'route_history') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminRouteHistoryScreen(),
                          ),
                        );
                      } else if (report['type'] == 'attendance_corrections') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AttendanceCorrectionScreen(),
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
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid() {
    return AdminOverviewMetrics(
      activeBusesCount: _activeBusesCount,
      studentsOnBoardCount: _totalCheckedIn,
    );
  }

  Widget _buildPerformanceMetric() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SchoolWayTheme.primary,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: SchoolWayTheme.primary.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: StreamBuilder<List<PlannedRoute>>(
        stream: FirebaseService.getPlannedRoutes(),
        builder: (context, routeSnap) {
          if (!routeSnap.hasData) {
            return Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(color: SchoolWayTheme.surface),
              ),
            );
          }
          final routesMap = {for (var r in routeSnap.data!) r.id: r};

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.routeSessionsCollection.snapshots(),
            builder: (context, sessionSnap) {
              String displayValue = '...';

              if (sessionSnap.hasData) {
                int totalCompleted = 0;
                int onTimeCompleted = 0;

                for (final doc in sessionSnap.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data['status'] == 'Completed') {
                    final routeId = data['routeId'] as String?;
                    if (routeId == null || !routesMap.containsKey(routeId)) {
                      // Skip free-roam or sessions with deleted routes
                      continue;
                    }
                    final expectedMins =
                        routesMap[routeId]!.expectedDurationMinutes;

                    final start = (data['startTime'] as Timestamp?)?.toDate();
                    final end = (data['endTime'] as Timestamp?)?.toDate();

                    if (start != null && end != null) {
                      totalCompleted++;
                      final duration = end.difference(start);
                      if (duration.inMinutes <= expectedMins) {
                        onTimeCompleted++;
                      }
                    }
                  }
                }

                if (totalCompleted > 0) {
                  final percentage = (onTimeCompleted / totalCompleted) * 100;
                  displayValue = '${percentage.toStringAsFixed(1)}%';
                } else {
                  displayValue = 'N/A';
                }
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context).onTimePerformance,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 16,
                            color: SchoolWayTheme.surface70,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          displayValue,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: SchoolWayTheme.surface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.trending_up,
                    color: SchoolWayTheme.surface,
                    size: 48,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildIncidentsSection() {
    final colors = context.schoolWayColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).recentIncidents,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: colors.headerText,
          ),
        ),
        SizedBox(height: 12),
        if (_recentIncidents.isEmpty)
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              AppLocalizations.of(context).noRecentIncidents,
              style: TextStyle(color: colors.mutedText, fontFamily: 'Lexend'),
            ),
          )
        else
          ..._recentIncidents.map((incident) => _buildIncidentTile(incident)),
      ],
    );
  }

  Widget _buildIncidentTile(IncidentReport incident) {
    final colors = context.schoolWayColors;

    Color getSeverityColor(String severity) {
      switch (severity.toLowerCase()) {
        case 'high':
          return SchoolWayTheme.danger;
        case 'medium':
          return SchoolWayTheme.warning;
        case 'low':
          return colors.badgeSuccess;
        default:
          return colors.mutedText;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      color: colors.cardBackground,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: getSeverityColor(
            incident.severity,
          ).withValues(alpha: 0.2),
          child: Icon(
            Icons.warning_amber_rounded,
            color: getSeverityColor(incident.severity),
          ),
        ),
        title: Text(
          incident.category,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            color: colors.headerText,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Text(
              incident.description,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13,
                color: colors.headerText,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Bus: ${incident.busId} • ${_formatTime(incident.timestamp)}',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 11,
                color: colors.mutedText,
              ),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class AdminOverviewMetrics extends StatelessWidget {
  const AdminOverviewMetrics({
    required this.activeBusesCount,
    required this.studentsOnBoardCount,
    super.key,
  });

  final int activeBusesCount;
  final int studentsOnBoardCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.schoolWayColors;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildMetricCard(
              key: const ValueKey('active-buses-metric-card'),
              title: 'Active Buses',
              value: '$activeBusesCount',
              icon: Icons.directions_bus,
              color: SchoolWayTheme.primary,
              colors: colors,
              shadowColor: Theme.of(context).shadowColor,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildMetricCard(
              key: const ValueKey('students-on-board-metric-card'),
              title: 'Students On Board',
              value: '$studentsOnBoardCount',
              icon: Icons.groups,
              color: SchoolWayTheme.successBright,
              colors: colors,
              shadowColor: Theme.of(context).shadowColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required Key key,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required SchoolWayColors colors,
    required Color shadowColor,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              color: colors.headerText,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminReportCard extends StatelessWidget {
  const AdminReportCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.schoolWayColors;
    return Material(
      color: SchoolWayTheme.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.cardBorder),
          ),
          child: DefaultTextStyle(
            style: TextStyle(fontFamily: 'Lexend', color: colors.headerText),
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
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 32),
                    ),
                    SizedBox(height: 16),
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.headerText,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      description,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13,
                        color: colors.mutedText,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Icon(Icons.arrow_forward, size: 20, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
