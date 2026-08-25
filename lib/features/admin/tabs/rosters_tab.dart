part of '../admin_home.dart';

class AdminRostersTab extends StatelessWidget {
  const AdminRostersTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).operationsManagement,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: SchoolWayTheme.navy,
            ),
          ),
          SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).manageBusesUsersAndStudents,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              color: SchoolWayTheme.primary,
            ),
          ),
          SizedBox(height: 24),
          // Quick Stats
          Text(
            AppLocalizations.of(context).quickOverview,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: SchoolWayTheme.navy,
            ),
          ),
          SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: swFirestore.collection('buses').snapshots(),
            builder: (context, busSnapshot) {
              return StreamBuilder<QuerySnapshot>(
                stream: swFirestore.collection('students').snapshots(),
                builder: (context, studentSnapshot) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: swFirestore.collection('users').snapshots(),
                    builder: (context, userSnapshot) {
                      final busCount = busSnapshot.data?.docs.length ?? 0;
                      final studentCount =
                          studentSnapshot.data?.docs.length ?? 0;
                      final userCount = userSnapshot.data?.docs.length ?? 0;

                      return Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: SchoolWayTheme.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.directions_bus,
                                    color: SchoolWayTheme.warning,
                                    size: 40,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '$busCount',
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: SchoolWayTheme.warning,
                                    ),
                                  ),
                                  Text(
                                    AppLocalizations.of(context).buses,
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      color: SchoolWayTheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: SchoolWayTheme.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.people,
                                    color: SchoolWayTheme.primary,
                                    size: 40,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '$userCount',
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: SchoolWayTheme.primary,
                                    ),
                                  ),
                                  Text(
                                    AppLocalizations.of(context).users,
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      color: SchoolWayTheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: SchoolWayTheme.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.child_care,
                                    color: SchoolWayTheme.accent,
                                    size: 40,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '$studentCount',
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: SchoolWayTheme.accent,
                                    ),
                                  ),
                                  Text(
                                    AppLocalizations.of(context).students,
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      color: SchoolWayTheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
          SizedBox(height: 24),
          // Bus Management Card
          _ManagementCard(
            title: 'Bus Management',
            description:
                'Manage fleet, assign drivers to buses, and track bus status.',
            icon: Icons.directions_bus,
            color: SchoolWayTheme.warning,
            borderColor: SchoolWayTheme.warning,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => BusManagementScreen()),
              );
            },
            stats: StreamBuilder<QuerySnapshot>(
              stream: swFirestore.collection('buses').snapshots(),
              builder: (context, snapshot) {
                final busCount = snapshot.data?.docs.length ?? 0;
                final activeBuses =
                    snapshot.data?.docs
                        .where(
                          (doc) =>
                              (doc.data()
                                  as Map<String, dynamic>?)?['status'] ==
                              'Active',
                        )
                        .length ??
                    0;
                final idleBuses =
                    snapshot.data?.docs
                        .where(
                          (doc) =>
                              (doc.data()
                                  as Map<String, dynamic>?)?['status'] ==
                              'Idle',
                        )
                        .length ??
                    0;
                return Row(
                  children: [
                    _StatChip('$busCount Total', SchoolWayTheme.muted),
                    SizedBox(width: 8),
                    _StatChip('$activeBuses Active', SchoolWayTheme.success),
                    SizedBox(width: 8),
                    _StatChip('$idleBuses Idle', SchoolWayTheme.warning),
                  ],
                );
              },
            ),
          ),
          SizedBox(height: 16),
          // Quick Setup Card
          _ManagementCard(
            title: AppLocalizations.of(context).quickSetup,
            description: AppLocalizations.of(context).quickSetupDescription,
            icon: Icons.bolt,
            color: SchoolWayTheme.primary,
            onTap: () {
              QuickSetupWizard.show(context);
            },
          ),
          SizedBox(height: 16),
          // User Management Card
          _ManagementCard(
            title: 'User Management',
            description:
                'Manage admins, drivers, and parents. Edit all user details and assign roles.',
            icon: Icons.people,
            color: SchoolWayTheme.success,
            borderColor: SchoolWayTheme.navy,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => UserManagementScreen()),
              );
            },
            stats: StreamBuilder<QuerySnapshot>(
              stream: swFirestore.collection('users').snapshots(),
              builder: (context, snapshot) {
                final userCount = snapshot.data?.docs.length ?? 0;
                final parents =
                    snapshot.data?.docs
                        .where(
                          (doc) =>
                              (doc.data() as Map<String, dynamic>?)?['role']
                                  ?.toString()
                                  .toLowerCase() ==
                              'parent',
                        )
                        .length ??
                    0;
                final drivers =
                    snapshot.data?.docs
                        .where(
                          (doc) =>
                              (doc.data() as Map<String, dynamic>?)?['role']
                                  ?.toString()
                                  .toLowerCase() ==
                              'driver',
                        )
                        .length ??
                    0;
                final admins =
                    snapshot.data?.docs
                        .where(
                          (doc) =>
                              (doc.data() as Map<String, dynamic>?)?['role']
                                  ?.toString()
                                  .toLowerCase() ==
                              'admin',
                        )
                        .length ??
                    0;
                return Row(
                  children: [
                    _StatChip('$userCount Total', SchoolWayTheme.muted),
                    SizedBox(width: 8),
                    _StatChip('$parents Parents', SchoolWayTheme.success),
                    SizedBox(width: 8),
                    _StatChip('$drivers Drivers', SchoolWayTheme.info),
                    SizedBox(width: 8),
                    _StatChip('$admins Admins', SchoolWayTheme.danger),
                  ],
                );
              },
            ),
          ),
          SizedBox(height: 16),
          // Student Management Card
          _ManagementCard(
            title: 'Student Management',
            description:
                'Add students, assign multiple parents, manage NFC tags, and assign buses.',
            icon: Icons.child_care,
            color: SchoolWayTheme.danger,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => StudentManagementScreen()),
              );
            },
            stats: StreamBuilder<QuerySnapshot>(
              stream: swFirestore.collection('students').snapshots(),
              builder: (context, snapshot) {
                final studentCount = snapshot.data?.docs.length ?? 0;
                final activeStudents =
                    snapshot.data?.docs
                        .where(
                          (doc) =>
                              (doc.data()
                                  as Map<String, dynamic>?)?['status'] ==
                              'Active',
                        )
                        .length ??
                    0;
                return Row(
                  children: [
                    _StatChip('$studentCount Total', SchoolWayTheme.muted),
                    SizedBox(width: 8),
                    _StatChip('$activeStudents Active', SchoolWayTheme.success),
                  ],
                );
              },
            ),
          ),
          SizedBox(height: 16),
          _ManagementCard(
            title: 'Route Planner',
            description:
                'Draw stops on the map, preview paths, and save routes for buses and assignments.',
            icon: Icons.alt_route,
            color: SchoolWayTheme.violet,
            borderColor: SchoolWayTheme.violetDark,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => RoutePlannerScreen()),
              );
            },
            stats: StreamBuilder<QuerySnapshot>(
              stream: swFirestore.collection('planned_routes').snapshots(),
              builder: (context, snapshot) {
                final routeCount = snapshot.data?.docs.length ?? 0;
                return Row(
                  children: [
                    _StatChip('$routeCount Saved routes', SchoolWayTheme.muted),
                  ],
                );
              },
            ),
          ),
          SizedBox(height: 16),
          _ManagementCard(
            title: 'CSV Management',
            description:
                'Import and export CSV data, plus rebuild saved route geometry with Google Maps.',
            icon: Icons.table_view_outlined,
            color: SchoolWayTheme.purple,
            borderColor: SchoolWayTheme.purpleDark,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => CsvImporterScreen()),
              );
            },
            stats: StreamBuilder<QuerySnapshot>(
              stream: swFirestore.collection('planned_routes').snapshots(),
              builder: (context, snapshot) {
                final routeCount = snapshot.data?.docs.length ?? 0;
                return Row(
                  children: [
                    _StatChip(
                      '$routeCount Routes available',
                      SchoolWayTheme.muted,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Reports Tab - Attendance, bus/driver NFC activity, emergency history

class _ManagementCard extends StatefulWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final Color? borderColor;
  final VoidCallback onTap;
  final Widget? stats;

  const _ManagementCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.borderColor,
    required this.onTap,
    this.stats,
  });

  @override
  State<_ManagementCard> createState() => _ManagementCardState();
}

class _ManagementCardState extends State<_ManagementCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _isPressed ? 0.98 : (_isHovered ? 1.02 : 1.0);

    return AnimatedScale(
      scale: scale,
      duration: Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ]
              : [],
        ),
        child: Material(
          color: SchoolWayTheme.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            onHover: (val) => setState(() => _isHovered = val),
            onHighlightChanged: (val) => setState(() => _isPressed = val),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: SchoolWayTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (widget.borderColor ?? widget.color).withValues(
                    alpha: 0.3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(widget.icon, color: widget.color, size: 32),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: SchoolWayTheme.navy,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              widget.description,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 13,
                                color: SchoolWayTheme.primary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: widget.color,
                        size: 18,
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Divider(height: 1),
                  SizedBox(height: 12),
                  if (widget.stats != null) widget.stats!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
