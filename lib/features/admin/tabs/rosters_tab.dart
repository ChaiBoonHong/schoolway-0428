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
          const Text(
            'Operations Management',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF03045E),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Manage buses, users, and students',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              color: Color(0xFF0077B6),
            ),
          ),
          const SizedBox(height: 24),
          // Quick Stats
          const Text(
            'Quick Overview',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF03045E),
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: swFirestore
                .collection('buses')
                .snapshots(),
            builder: (context, busSnapshot) {
              return StreamBuilder<QuerySnapshot>(
                stream: swFirestore
                    .collection('students')
                    .snapshots(),
                builder: (context, studentSnapshot) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: swFirestore
                        .collection('users')
                        .snapshots(),
                    builder: (context, userSnapshot) {
                      final busCount = busSnapshot.data?.docs.length ?? 0;
                      final studentCount = studentSnapshot.data?.docs.length ?? 0;
                      final userCount = userSnapshot.data?.docs.length ?? 0;

                      return Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.directions_bus, color: Colors.orange, size: 40),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$busCount',
                                    style: const TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange,
                                    ),
                                  ),
                                  const Text(
                                    'Buses',
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      color: Color(0xFF0077B6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.people, color: Color(0xFF0077B6), size: 40),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$userCount',
                                    style: const TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0077B6),
                                    ),
                                  ),
                                  const Text(
                                    'Users',
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      color: Color(0xFF0077B6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.child_care, color: Color(0xFF00B4D8), size: 40),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$studentCount',
                                    style: const TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF00B4D8),
                                    ),
                                  ),
                                  const Text(
                                    'Students',
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      color: Color(0xFF0077B6),
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
          const SizedBox(height: 24),
          // Bus Management Card
          _ManagementCard(
            title: 'Bus Management',
            description: 'Manage fleet, assign drivers to buses, and track bus status.',
            icon: Icons.directions_bus,
            color: Colors.yellow.shade700,
            borderColor: Colors.orange,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BusManagementScreen(),
                ),
              );
            },
            stats: StreamBuilder<QuerySnapshot>(
              stream: swFirestore
                  .collection('buses')
                  .snapshots(),
              builder: (context, snapshot) {
                final busCount = snapshot.data?.docs.length ?? 0;
                final activeBuses = snapshot.data?.docs
                    .where((doc) => (doc.data() as Map<String, dynamic>?)
                        ?['status'] == 'Active')
                    .length ?? 0;
                final idleBuses = snapshot.data?.docs
                    .where((doc) => (doc.data() as Map<String, dynamic>?)
                        ?['status'] == 'Idle')
                    .length ?? 0;
                return Row(
                  children: [
                    _StatChip('$busCount Total', Colors.grey),
                    const SizedBox(width: 8),
                    _StatChip('$activeBuses Active', Colors.green),
                    const SizedBox(width: 8),
                    _StatChip('$idleBuses Idle', Colors.orange),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // User Management Card
          _ManagementCard(
            title: 'User Management',
            description: 'Manage admins, drivers, and parents. Edit all user details and assign roles.',
            icon: Icons.people,
            color: Colors.green,
            borderColor: const Color(0xFF03045E),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const UserManagementScreen(),
                ),
              );
            },
            stats: StreamBuilder<QuerySnapshot>(
              stream: swFirestore
                  .collection('users')
                  .snapshots(),
              builder: (context, snapshot) {
                final userCount = snapshot.data?.docs.length ?? 0;
                final parents = snapshot.data?.docs
                    .where((doc) => (doc.data() as Map<String, dynamic>?)
                        ?['role']?.toString().toLowerCase() == 'parent')
                    .length ?? 0;
                final drivers = snapshot.data?.docs
                    .where((doc) => (doc.data() as Map<String, dynamic>?)
                        ?['role']?.toString().toLowerCase() == 'driver')
                    .length ?? 0;
                final admins = snapshot.data?.docs
                    .where((doc) => (doc.data() as Map<String, dynamic>?)
                        ?['role']?.toString().toLowerCase() == 'admin')
                    .length ?? 0;
                return Row(
                  children: [
                    _StatChip('$userCount Total', Colors.grey),
                    const SizedBox(width: 8),
                    _StatChip('$parents Parents', Colors.green),
                    const SizedBox(width: 8),
                    _StatChip('$drivers Drivers', Colors.blue),
                    const SizedBox(width: 8),
                    _StatChip('$admins Admins', Colors.red),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // Student Management Card
          _ManagementCard(
            title: 'Student Management',
            description: 'Add students, assign multiple parents, manage NFC tags, and assign buses.',
            icon: Icons.child_care,
            color: Colors.red,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StudentManagementScreen(),
                ),
              );
            },
            stats: StreamBuilder<QuerySnapshot>(
              stream: swFirestore
                  .collection('students')
                  .snapshots(),
              builder: (context, snapshot) {
                final studentCount = snapshot.data?.docs.length ?? 0;
                final activeStudents = snapshot.data?.docs
                    .where((doc) => (doc.data() as Map<String, dynamic>?)
                        ?['status'] == 'Active')
                    .length ?? 0;
                return Row(
                  children: [
                    _StatChip('$studentCount Total', Colors.grey),
                    const SizedBox(width: 8),
                    _StatChip('$activeStudents Active', Colors.green),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _ManagementCard(
            title: 'Route Planner',
            description:
                'Draw stops on the map, preview paths, and save routes for buses and assignments.',
            icon: Icons.alt_route,
            color: const Color(0xFF7C3AED),
            borderColor: const Color(0xFF5B21B6),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const RoutePlannerScreen(),
                ),
              );
            },
            stats: StreamBuilder<QuerySnapshot>(
              stream: swFirestore.collection('planned_routes').snapshots(),
              builder: (context, snapshot) {
                final routeCount = snapshot.data?.docs.length ?? 0;
                return Row(
                  children: [
                    _StatChip('$routeCount Saved routes', Colors.grey),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _ManagementCard(
            title: 'CSV Management',
            description:
                'Import and export CSV data, plus rebuild saved route geometry with OSRM.',
            icon: Icons.table_view_outlined,
            color: const Color(0xFF6A1B9A),
            borderColor: const Color(0xFF4A148C),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const CsvImporterScreen(),
                ),
              );
            },
            stats: StreamBuilder<QuerySnapshot>(
              stream: swFirestore.collection('planned_routes').snapshots(),
              builder: (context, snapshot) {
                final routeCount = snapshot.data?.docs.length ?? 0;
                return Row(
                  children: [
                    _StatChip('$routeCount Routes available', Colors.grey),
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

class _ManagementCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final Color? borderColor;
  final VoidCallback onTap;
  final Widget stats;

  const _ManagementCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.borderColor,
    required this.onTap,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (borderColor ?? color).withValues(alpha: 0.3),
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
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF03045E),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13,
                          color: Color(0xFF0077B6),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: color,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            stats,
          ],
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
