import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/features/parent/parent_trip_event_map_screen.dart';
import 'package:schoolway/services/boarding_record_service.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> _openBoardingLocationInMaps(
  BuildContext context,
  EventLocation location,
) async {
  if (!location.hasValidCoordinates) return;
  final uri = Uri.parse(
    'https://www.google.com/maps?q=${location.latitude},${location.longitude}',
  );
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open Maps',
          style: TextStyle(fontFamily: 'Lexend'),
        ),
      ),
    );
  }
}

String? _stopLabel(EventLocation location) {
  final n = location.name.trim();
  if (n.isEmpty || n == 'Unknown' || n == 'GPS') return null;
  return n;
}

class ParentTripHistoryTab extends StatelessWidget {
  const ParentTripHistoryTab({super.key, this.focusStudentId});

  final String? focusStudentId;

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return const Center(
        child: Text('Please sign in', style: TextStyle(fontFamily: 'Lexend')),
      );
    }

    return StreamBuilder<List<Student>>(
      stream: FirebaseService.getStudentsByParentAuthUid(currentUserId),
      builder: (context, studentsSnapshot) {
        if (studentsSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF0077B6)),
          );
        }

        if (studentsSnapshot.hasError) {
          return Center(
            child: Text(
              'Error loading students: ${studentsSnapshot.error}',
              style: const TextStyle(fontFamily: 'Lexend'),
            ),
          );
        }

        final students = studentsSnapshot.data ?? const <Student>[];
        if (students.isEmpty) {
          return _buildEmptyState();
        }

        if (students.length == 1) {
          return _StudentTripTimeline(student: students.first);
        }

        final focusId = focusStudentId?.trim();
        var initialIndex = 0;
        if (focusId != null && focusId.isNotEmpty) {
          final idx = students.indexWhere((s) => s.id == focusId);
          if (idx >= 0) {
            initialIndex = idx;
          }
        }

        return DefaultTabController(
          key: ValueKey('trip-$focusId-${students.length}'),
          length: students.length,
          initialIndex: initialIndex,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  isScrollable: students.length > 3,
                  labelColor: const Color(0xFF0077B6),
                  unselectedLabelColor: const Color(0xFF999999),
                  indicatorColor: const Color(0xFF0077B6),
                  labelStyle: const TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                  ),
                  tabs: students.map((s) => Tab(text: s.firstName)).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  children: students
                      .map((s) => _StudentTripTimeline(student: s))
                      .toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_outlined,
                size: 100,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Trip History',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No children found for trip history',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 16,
                color: Color(0xFF0077B6),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentTripTimeline extends StatelessWidget {
  const _StudentTripTimeline({required this.student});

  final Student student;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BoardingEvent>>(
      stream: FirebaseService.getBoardingEventsByStudent(student.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF0077B6)),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading history',
              style: const TextStyle(fontFamily: 'Lexend', color: Colors.red),
            ),
          );
        }

        final events = snapshot.data ?? const <BoardingEvent>[];
        if (events.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bus_alert_outlined,
                    size: 64,
                    color: Colors.grey.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No boarding records yet',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 16,
                      color: Color(0xFF999999),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final grouped = _groupByDate(events);
        final routeHistory = _routeHistoryEvents(events);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _RouteHistorySection(student: student, events: routeHistory),
            const SizedBox(height: 20),
            ...grouped.asMap().entries.map(
              (entry) => _DateSection(
                student: student,
                date: entry.value.date,
                events: entry.value.events,
                isFirst: entry.key == 0,
              ),
            ),
          ],
        );
      },
    );
  }

  List<BoardingEvent> _routeHistoryEvents(List<BoardingEvent> events) {
    final bySession = <String, BoardingEvent>{};
    for (final event in events) {
      final sessionId = event.sessionId?.trim() ?? '';
      if (sessionId.isEmpty) continue;
      final current = bySession[sessionId];
      if (current == null || event.timestamp.isAfter(current.timestamp)) {
        bySession[sessionId] = event;
      }
    }
    return bySession.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<_DateGroup> _groupByDate(List<BoardingEvent> events) {
    final map = <String, List<BoardingEvent>>{};
    for (final e in events) {
      final key = DateFormat('yyyy-MM-dd').format(e.timestamp);
      map.putIfAbsent(key, () => []).add(e);
    }
    final sorted = map.entries.toList()..sort((a, b) => b.key.compareTo(a.key));

    return sorted.map((e) {
      final date = DateFormat('yyyy-MM-dd').parse(e.key);
      return _DateGroup(date: date, events: e.value);
    }).toList();
  }
}

class _RouteHistorySection extends StatelessWidget {
  const _RouteHistorySection({required this.student, required this.events});

  final Student student;
  final List<BoardingEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Route History',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF03045E),
          ),
        ),
        const SizedBox(height: 8),
        ...events.map(
          (event) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 1,
            child: ListTile(
              leading: const Icon(Icons.route, color: Color(0xFF0077B6)),
              title: Text(
                DateFormat('EEE, d MMM yyyy').format(event.timestamp),
                style: const TextStyle(fontFamily: 'Lexend'),
              ),
              subtitle: Text(
                '${BoardingRecordService.isBoardingEventType(event.eventType) ? 'Boarding' : 'Trip'} · ${_stopLabel(event.location) ?? 'Route recorded'}',
                style: const TextStyle(fontFamily: 'Lexend', fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ParentTripEventMapScreen(event: event, student: student),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateGroup {
  final DateTime date;
  final List<BoardingEvent> events;

  const _DateGroup({required this.date, required this.events});
}

class _DateSection extends StatelessWidget {
  const _DateSection({
    required this.student,
    required this.date,
    required this.events,
    required this.isFirst,
  });

  final Student student;
  final DateTime date;
  final List<BoardingEvent> events;
  final bool isFirst;

  String _dateLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEEE').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final dayName = _dateLabel();
    final dateStr = DateFormat('d MMM yyyy').format(date);

    final boardCount = events
        .where((e) => BoardingRecordService.isBoardingEventType(e.eventType))
        .length;
    final dropOffCount = events
        .where((e) => BoardingRecordService.isAlightingEventType(e.eventType))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isFirst) const SizedBox(height: 20),

        // Date header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0077B6), Color(0xFF00B4D8)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dayName,
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              _CountChip(
                icon: Icons.login,
                count: boardCount,
                color: const Color(0xFF4CAF50),
              ),
              const SizedBox(width: 8),
              _CountChip(
                icon: Icons.logout,
                count: dropOffCount,
                color: const Color(0xFFFF9800),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Event cards
        ...events.asMap().entries.map((entry) {
          final idx = entry.key;
          final event = entry.value;
          return _EventCard(
            student: student,
            event: event,
            isLast: idx == events.length - 1,
          );
        }),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.icon,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.student,
    required this.event,
    required this.isLast,
  });

  final Student student;
  final BoardingEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isBoarded = BoardingRecordService.isBoardingEventType(
      event.eventType,
    );
    final color = isBoarded ? const Color(0xFF4CAF50) : const Color(0xFFFF9800);
    final label = isBoarded ? 'Boarded' : 'Dropped Off';
    final icon = isBoarded ? Icons.login : Icons.logout;
    final timeFmt = DateFormat('hh:mm a').format(event.timestamp);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline gutter
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 36,
                    color: Colors.grey.withValues(alpha: 0.15),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Card body
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                            if (_stopLabel(event.location) != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                _stopLabel(event.location)!,
                                style: const TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 12,
                                  color: Color(0xFF03045E),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F7FA),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          timeFmt,
                          style: const TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0077B6),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (event.location.hasValidCoordinates) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.pin_drop_outlined,
                          size: 16,
                          color: Color(0xFF0077B6),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: SelectableText(
                            '${event.location.latitude.toStringAsFixed(6)}, '
                            '${event.location.longitude.toStringAsFixed(6)}',
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12,
                              height: 1.35,
                              color: Color(0xFF03045E),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () =>
                          _openBoardingLocationInMaps(context, event.location),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.map_outlined,
                              size: 18,
                              color: Color(0xFF0077B6),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Open in Google Maps',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0077B6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (!event.location.hasValidCoordinates &&
                      _stopLabel(event.location) == null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Exact location not recorded for this scan.',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        PageRouteBuilder<void>(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  ParentTripEventMapScreen(
                                    event: event,
                                    student: student,
                                  ),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                                const begin = Offset(0.0, 1.0);
                                const end = Offset.zero;
                                const curve = Curves.easeInOut;

                                var tween = Tween(
                                  begin: begin,
                                  end: end,
                                ).chain(CurveTween(curve: curve));
                                var slideAnimation = animation.drive(tween);

                                return SlideTransition(
                                  position: slideAnimation,
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                );
                              },
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: const [
                          Icon(Icons.route, size: 18, color: Color(0xFF03045E)),
                          SizedBox(width: 6),
                          Text(
                            'View route history',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF03045E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
