import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import '../../core/school_classes.dart';
import '../../models/models.dart';
import '../../services/boarding_record_service.dart';
import '../../services/firebase_service.dart';

class ReportsScreen extends StatefulWidget {
  final String reportType;

  const ReportsScreen({super.key, required this.reportType});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTimeRange _selectedDateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 6)),
    end: DateTime.now(),
  );

  bool get _usesDatePicker =>
      widget.reportType == 'daily' ||
      widget.reportType == 'bus_activity' ||
      widget.reportType == 'driver_activity';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFCAF0F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFCAF0F8),
        elevation: 0,
        foregroundColor: const Color(0xFF03045E),
        title: Text(
          _getReportTitle(),
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: Color(0xFF03045E),
          ),
        ),
        actions: [
          if (_usesDatePicker)
            IconButton(
              icon: const Icon(Icons.calendar_today),
              tooltip: 'Choose date',
              onPressed: () async {
                if (widget.reportType == 'bus_activity' || widget.reportType == 'driver_activity') {
                  final range = await showDateRangePicker(
                    context: context,
                    initialDateRange: _selectedDateRange,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                  );
                  if (range != null) {
                    setState(() => _selectedDateRange = range);
                  }
                } else {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    setState(() => _selectedDate = date);
                  }
                }
              },
            ),
        ],
      ),
      body: _buildReportContent(),
    );
  }

  String _getReportTitle() {
    switch (widget.reportType) {
      case 'daily':
        return 'Daily Attendance Report';
      case 'bus_activity':
        return 'Bus Activity';
      case 'driver_activity':
        return 'Driver Activity';
      case 'emergency_history':
        return 'Emergency Alert History';
      case 'exceptions_audit':
        return 'Daily Exceptions & Audit Logs';
      default:
        return 'Report';
    }
  }

  Widget _buildReportContent() {
    switch (widget.reportType) {
      case 'daily':
        return _DailyAttendanceReport(date: _selectedDate);
      case 'bus_activity':
        return _BusActivityReport(dateRange: _selectedDateRange);
      case 'driver_activity':
        return _DriverActivityReport(dateRange: _selectedDateRange);
      case 'emergency_history':
        return const _EmergencyAlertHistoryReport();
      case 'exceptions_audit':
        return const _ExceptionsAndAuditLogsReport();

      default:
        return const Center(
          child: Text(
            'Unknown report type',
            style: TextStyle(
              fontFamily: 'Lexend',
              color: Color(0xFF03045E),
            ),
          ),
        );
    }
  }
}

/// Computes [startInclusive, endExclusive) based on the given DateTimeRange.
(DateTime startInclusive, DateTime endExclusive) _dateRangeWindow(
  DateTimeRange range,
) {
  final startInclusive =
      DateTime(range.start.year, range.start.month, range.start.day);
  final endExclusive =
      DateTime(range.end.year, range.end.month, range.end.day).add(const Duration(days: 1));
  return (startInclusive, endExclusive);
}

Future<Map<String, String>> _resolveDriverLabels(Iterable<String> driverIds) async {
  final out = <String, String>{};
  for (final id in driverIds.toSet()) {
    if (id.isEmpty) continue;
    final data = await FirebaseService.getUserDataByAuthUid(id);
    if (data != null) {
      final fn = '${data['firstName'] ?? ''}'.trim();
      final ln = '${data['lastName'] ?? ''}'.trim();
      final name = '$fn $ln'.trim();
      out[id] = name.isNotEmpty ? name : id;
    } else {
      out[id] = id.length > 14 ? '${id.substring(0, 12)}…' : id;
    }
  }
  return out;
}

void _accumulateEventCounts(
  Map<String, dynamic> data,
  Map<String, int> board,
  Map<String, int> alight,
  Map<String, int> total,
  String key,
) {
  final t = data['eventType'] as String?;
  total[key] = (total[key] ?? 0) + 1;
  if (BoardingRecordService.isBoardingEventType(t)) {
    board[key] = (board[key] ?? 0) + 1;
  } else if (BoardingRecordService.isAlightingEventType(t)) {
    alight[key] = (alight[key] ?? 0) + 1;
  }
}

enum _DayAttendanceStatus { board, alight, absent }

class _DailyAttendanceReport extends StatefulWidget {
  final DateTime date;

  const _DailyAttendanceReport({required this.date});

  @override
  State<_DailyAttendanceReport> createState() => _DailyAttendanceReportState();
}

class _DailyAttendanceReportState extends State<_DailyAttendanceReport> {
  /// `null` means all classes.
  String? _classFilter;

  static bool _studentIsActive(Student s) {
    return s.status.trim().toLowerCase() != 'inactive';
  }

  static Map<String, List<QueryDocumentSnapshot>> _eventsByStudentId(
    List<QueryDocumentSnapshot> docs,
  ) {
    final map = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in docs) {
      final sid = doc['studentId'] as String? ?? '';
      if (sid.isEmpty) continue;
      map.putIfAbsent(sid, () => []).add(doc);
    }
    for (final list in map.values) {
      list.sort(
        (a, b) => (a['timestamp'] as Timestamp).compareTo(
          b['timestamp'] as Timestamp,
        ),
      );
    }
    return map;
  }

  static _DayAttendanceStatus _statusForDay(
    List<QueryDocumentSnapshot> sortedDayEvents,
  ) {
    if (sortedDayEvents.isEmpty) return _DayAttendanceStatus.absent;
    final last = sortedDayEvents.last;
    final type = last['eventType'] as String?;
    if (BoardingRecordService.isAlightingEventType(type)) {
      return _DayAttendanceStatus.alight;
    }
    if (BoardingRecordService.isBoardingEventType(type)) {
      return _DayAttendanceStatus.board;
    }
    return _DayAttendanceStatus.absent;
  }

  static String _statusLabel(_DayAttendanceStatus s) {
    switch (s) {
      case _DayAttendanceStatus.board:
        return 'Board';
      case _DayAttendanceStatus.alight:
        return 'Drop Off';
      case _DayAttendanceStatus.absent:
        return 'Absent';
    }
  }

  static Color _statusColor(_DayAttendanceStatus s) {
    switch (s) {
      case _DayAttendanceStatus.board:
        return Colors.green;
      case _DayAttendanceStatus.alight:
        return Colors.orange;
      case _DayAttendanceStatus.absent:
        return Colors.grey;
    }
  }

  static (int board, int alight, int absent) _statusCountsForStudents(
    List<Student> students,
    Map<String, List<QueryDocumentSnapshot>> byStudent,
  ) {
    var board = 0;
    var alight = 0;
    var absent = 0;
    for (final s in students) {
      switch (_statusForDay(byStudent[s.id] ?? [])) {
        case _DayAttendanceStatus.board:
          board++;
          break;
        case _DayAttendanceStatus.alight:
          alight++;
          break;
        case _DayAttendanceStatus.absent:
          absent++;
          break;
      }
    }
    return (board, alight, absent);
  }

  void _showStudentActionTimes(
    BuildContext context,
    Student student,
    List<QueryDocumentSnapshot> sortedDayEvents,
  ) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          student.fullName,
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            color: Color(0xFF03045E),
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sortedDayEvents.isEmpty)
                const Text(
                  'No bus actions recorded on this date.',
                  style: TextStyle(fontFamily: 'Lexend'),
                )
              else
                ...sortedDayEvents.map((e) {
                  final data = e.data() as Map<String, dynamic>;
                  final dt = (data['timestamp'] as Timestamp).toDate();
                  final type = data['eventType'] as String? ?? '';
                  final label = BoardingRecordService.isBoardingEventType(type)
                      ? 'Board'
                      : BoardingRecordService.isAlightingEventType(type)
                          ? 'Drop Off'
                          : type;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '$label — ${fmt.format(dt)}',
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        color: Color(0xFF0077B6),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Close',
              style: TextStyle(fontFamily: 'Lexend'),
            ),
          ),
        ],
      ),
    );
  }

  List<Student> _studentsInClass(List<Student> students, String classId) {
    return students
        .where(
          (s) =>
              _studentIsActive(s) &&
              (s.classId != null && s.classId!.trim() == classId),
        )
        .toList()
      ..sort((a, b) {
        final c = a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
        if (c != 0) return c;
        return a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
      });
  }

  List<Student> _unassignedStudents(List<Student> students) {
    return students
        .where(
          (s) =>
              _studentIsActive(s) &&
              (s.classId == null || s.classId!.trim().isEmpty),
        )
        .toList()
      ..sort((a, b) {
        final c = a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
        if (c != 0) return c;
        return a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
      });
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.date;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return StreamBuilder<QuerySnapshot>(
      stream: swFirestore
          .collection('boarding_events')
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('timestamp', descending: false)
          .snapshots(),
      builder: (context, eventSnap) {
        if (eventSnap.hasError) {
          return Center(
            child: Text(
              'Error: ${eventSnap.error}',
              style: const TextStyle(
                fontFamily: 'Lexend',
                color: Color(0xFF03045E),
              ),
            ),
          );
        }

        if (eventSnap.connectionState == ConnectionState.waiting &&
            !eventSnap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF0077B6)),
          );
        }

        return StreamBuilder<List<Student>>(
          stream: FirebaseService.getAllStudents(),
          builder: (context, studentSnap) {
            if (studentSnap.hasError) {
              return Center(
                child: Text(
                  'Error: ${studentSnap.error}',
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    color: Color(0xFF03045E),
                  ),
                ),
              );
            }

            if (studentSnap.connectionState == ConnectionState.waiting &&
                !studentSnap.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF0077B6)),
              );
            }

            final allStudents = studentSnap.data ?? [];
            final eventDocs = eventSnap.data?.docs ?? [];
            final byStudent = _eventsByStudentId(eventDocs);

            final rosterStudents = <Student>[];
            if (_classFilter != null) {
              rosterStudents.addAll(
                _studentsInClass(allStudents, _classFilter!),
              );
            } else {
              for (final cid in kSchoolClassIds) {
                rosterStudents.addAll(_studentsInClass(allStudents, cid));
              }
              rosterStudents.addAll(_unassignedStudents(allStudents));
            }

            var board = 0;
            var alight = 0;
            var absent = 0;
            for (final s in rosterStudents) {
              final st = _statusForDay(byStudent[s.id] ?? []);
              switch (st) {
                case _DayAttendanceStatus.board:
                  board++;
                  break;
                case _DayAttendanceStatus.alight:
                  alight++;
                  break;
                case _DayAttendanceStatus.absent:
                  absent++;
                  break;
              }
            }

            Widget buildStudentTile(Student s) {
              final dayEvents = byStudent[s.id] ?? [];
              final status = _statusForDay(dayEvents);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showStudentActionTimes(context, s, dayEvents),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.fullName,
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF03045E),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor(status).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _statusColor(status).withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            _statusLabel(status),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _statusColor(status),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            Widget buildClassSection(
              String sectionKey,
              String classLabel,
              List<Student> students,
            ) {
              final counts = _statusCountsForStudents(students, byStudent);
              final subtitle = students.isEmpty
                  ? 'No students'
                  : '${students.length} students · Board ${counts.$1} · '
                      'Drop Off ${counts.$2} · Absent ${counts.$3}';

              return Card(
                key: ValueKey<String>('daily_attendance_class_$sectionKey'),
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  initiallyExpanded: false,
                  iconColor: const Color(0xFF0077B6),
                  collapsedIconColor: const Color(0xFF0077B6),
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  title: Text(
                    classLabel,
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF03045E),
                    ),
                  ),
                  subtitle: Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13,
                      color: Color(0xFF0077B6),
                    ),
                  ),
                  children: [
                    if (students.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8, left: 4, right: 4),
                        child: Text(
                          'No students in this class',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            color: Color(0xFF0077B6),
                          ),
                        ),
                      )
                    else
                      ...students.map(buildStudentTile),
                  ],
                ),
              );
            }

            final bodyChildren = <Widget>[
              _dailyReportDateHeader(date),
              const SizedBox(height: 16),
              _dailyClassFilterDropdown(),
              if (_classFilter != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Showing class $_classFilter only',
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13,
                    color: Color(0xFF0077B6),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      title: 'Board',
                      value: board.toString(),
                      icon: Icons.login,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Drop Off',
                      value: alight.toString(),
                      icon: Icons.logout,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Absent',
                      value: absent.toString(),
                      icon: Icons.person_off_outlined,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Attendance by class',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF03045E),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tap a class to expand the roster. Tap a student for action times.',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13,
                  color: Color(0xFF0077B6),
                ),
              ),
            ];

            if (_classFilter != null) {
              final students = _studentsInClass(allStudents, _classFilter!);
              bodyChildren.add(
                buildClassSection(_classFilter!, 'Class $_classFilter', students),
              );
            } else {
              for (final cid in kSchoolClassIds) {
                bodyChildren.add(
                  buildClassSection(
                    cid,
                    'Class $cid',
                    _studentsInClass(allStudents, cid),
                  ),
                );
              }
              final unassigned = _unassignedStudents(allStudents);
              if (unassigned.isNotEmpty) {
                bodyChildren.add(
                  buildClassSection('unassigned', 'Unassigned class', unassigned),
                );
              }
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: bodyChildren,
              ),
            );
          },
        );
      },
    );
  }

  Widget _dailyReportDateHeader(DateTime date) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0077B6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, color: Colors.white, size: 32),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Report Date',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              Text(
                DateFormat('EEEE, MMMM d, y').format(date),
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dailyClassFilterDropdown() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Text(
              'Class',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w600,
                color: Color(0xFF03045E),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String?>(
                value: _classFilter,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                hint: const Text(
                  'All classes',
                  style: TextStyle(fontFamily: 'Lexend'),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      'All classes',
                      style: TextStyle(fontFamily: 'Lexend'),
                    ),
                  ),
                  ...kSchoolClassIds.map(
                    (c) => DropdownMenuItem<String?>(
                      value: c,
                      child:
                          Text(c, style: const TextStyle(fontFamily: 'Lexend')),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _classFilter = value;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusActivityReport extends StatelessWidget {
  final DateTimeRange dateRange;

  const _BusActivityReport({required this.dateRange});

  @override
  Widget build(BuildContext context) {
    final (start, end) = _dateRangeWindow(dateRange);

    return StreamBuilder<List<Bus>>(
      stream: FirebaseService.getBuses(),
      builder: (context, busSnap) {
        if (busSnap.connectionState == ConnectionState.waiting && !busSnap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF0077B6)),
          );
        }
        final buses = busSnap.data ?? [];

        return StreamBuilder<QuerySnapshot>(
          stream: swFirestore
              .collection('boarding_events')
              .where('timestamp',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(start))
              .where('timestamp', isLessThan: Timestamp.fromDate(end))
              .snapshots(),
          builder: (context, eventSnap) {
            if (eventSnap.hasError) {
              return Center(
                child: Text(
                  'Error: ${eventSnap.error}',
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    color: Color(0xFF03045E),
                  ),
                ),
              );
            }
            if (eventSnap.connectionState == ConnectionState.waiting &&
                !eventSnap.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF0077B6)),
              );
            }

            final board = <String, int>{};
            final alight = <String, int>{};
            final total = <String, int>{};

            for (final doc in eventSnap.data?.docs ?? []) {
              final data = doc.data() as Map<String, dynamic>;
              final busId = data['busId'] as String? ?? '';
              if (busId.isEmpty) continue;
              _accumulateEventCounts(data, board, alight, total, busId);
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReportPeriodHeader(
                    title: '7-day window (boarding scans)',
                    subtitle:
                        '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, y').format(end)}',
                    color: const Color(0xFF0077B6),
                    icon: Icons.date_range,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'NFC board and drop off counts per bus. Use the calendar to move the 7-day window.',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13,
                      color: Color(0xFF0077B6),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (buses.isEmpty)
                    const Text(
                      'No buses registered.',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: Color(0xFF0077B6),
                      ),
                    )
                  else
                    ...buses.map((bus) {
                      final b = board[bus.id] ?? 0;
                      final a = alight[bus.id] ?? 0;
                      final t = total[bus.id] ?? 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.directions_bus,
                                    color: bus.status == 'Active'
                                        ? Colors.green
                                        : Colors.grey,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          bus.busNumber,
                                          style: const TextStyle(
                                            fontFamily: 'Lexend',
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF03045E),
                                          ),
                                        ),
                                        Text(
                                          bus.currentRoute ??
                                              'No route assigned',
                                          style: const TextStyle(
                                            fontFamily: 'Lexend',
                                            fontSize: 13,
                                            color: Color(0xFF0077B6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _StatItem(
                                    label: 'Board',
                                    value: b.toString(),
                                    color: Colors.green,
                                  ),
                                  _StatItem(
                                    label: 'Drop Off',
                                    value: a.toString(),
                                    color: Colors.orange,
                                  ),
                                  _StatItem(
                                    label: 'Total',
                                    value: t.toString(),
                                    color: const Color(0xFF0077B6),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DriverActivityReport extends StatelessWidget {
  final DateTimeRange dateRange;

  const _DriverActivityReport({required this.dateRange});

  @override
  Widget build(BuildContext context) {
    final (start, end) = _dateRangeWindow(dateRange);

    return StreamBuilder<QuerySnapshot>(
      stream: swFirestore
          .collection('boarding_events')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('timestamp', isLessThan: Timestamp.fromDate(end))
          .snapshots(),
      builder: (context, eventSnap) {
        if (eventSnap.hasError) {
          return Center(
            child: Text(
              'Error: ${eventSnap.error}',
              style: const TextStyle(
                fontFamily: 'Lexend',
                color: Color(0xFF03045E),
              ),
            ),
          );
        }
        if (eventSnap.connectionState == ConnectionState.waiting &&
            !eventSnap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF0077B6)),
          );
        }

        final board = <String, int>{};
        final alight = <String, int>{};
        final total = <String, int>{};

        for (final doc in eventSnap.data?.docs ?? []) {
          final data = doc.data() as Map<String, dynamic>;
          final driverId = data['driverId'] as String? ?? '';
          if (driverId.isEmpty) continue;
          _accumulateEventCounts(data, board, alight, total, driverId);
        }

        final driverIds = total.keys.toList()
          ..sort((a, b) => (total[b] ?? 0).compareTo(total[a] ?? 0));

        return FutureBuilder<Map<String, String>>(
          future: _resolveDriverLabels(driverIds),
          builder: (context, nameSnap) {
            if (nameSnap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF0077B6)),
              );
            }
            final labels = nameSnap.data ?? {};

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReportPeriodHeader(
                    title: '7-day window (per driver)',
                    subtitle:
                        '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, y').format(end)}',
                    color: const Color(0xFF00B4D8),
                    icon: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Counts of NFC scans recorded under each driver account.',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13,
                      color: Color(0xFF0077B6),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (driverIds.isEmpty)
                    const Text(
                      'No driver-attributed scans in this period.',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: Color(0xFF0077B6),
                      ),
                    )
                  else
                    ...driverIds.map((id) {
                      final b = board[id] ?? 0;
                      final a = alight[id] ?? 0;
                      final t = total[id] ?? 0;
                      final label = labels[id] ?? id;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: const TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF03045E),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _StatItem(
                                    label: 'Board',
                                    value: b.toString(),
                                    color: Colors.green,
                                  ),
                                  _StatItem(
                                    label: 'Drop Off',
                                    value: a.toString(),
                                    color: Colors.orange,
                                  ),
                                  _StatItem(
                                    label: 'Total',
                                    value: t.toString(),
                                    color: const Color(0xFF0077B6),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _EmergencyAlertHistoryReport extends StatelessWidget {
  const _EmergencyAlertHistoryReport();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: swFirestore
          .collection('emergency_alerts')
          .orderBy('timestamp', descending: true)
          .limit(80)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error: ${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  color: Color(0xFF03045E),
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF0077B6)),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReportPeriodHeader(
                title: 'Recent alerts',
                subtitle: 'Newest first (up to 80 records)',
                color: Colors.red.shade700,
                icon: Icons.emergency_outlined,
              ),
              const SizedBox(height: 8),
              const Text(
                'Driver-triggered emergencies. Resolve active items from Emergency alerts.',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13,
                  color: Color(0xFF0077B6),
                ),
              ),
              const SizedBox(height: 16),
              if (docs.isEmpty)
                const Text(
                  'No emergency alerts recorded.',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    color: Color(0xFF0077B6),
                  ),
                )
              else
                ...docs.map((doc) {
                  final alert = EmergencyAlert.fromFirestore(doc);
                  final active = alert.isActive;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: active
                            ? Colors.red.withValues(alpha: 0.15)
                            : Colors.grey.withValues(alpha: 0.15),
                        child: Icon(
                          Icons.emergency,
                          color: active ? Colors.red : Colors.grey,
                        ),
                      ),
                      title: Text(
                        DateFormat('yyyy-MM-dd HH:mm')
                            .format(alert.timestamp),
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF03045E),
                        ),
                      ),
                      subtitle: Text(
                        'Bus ${alert.busId}\n'
                        '${alert.status}'
                        '${alert.resolvedAt != null ? ' · ${DateFormat('yyyy-MM-dd HH:mm').format(alert.resolvedAt!)}' : ''}',
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          color: Color(0xFF0077B6),
                          height: 1.35,
                        ),
                      ),
                      isThreeLine: true,
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _ReportPeriodHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;

  const _ReportPeriodHeader({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12,
              color: Color(0xFF0077B6),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 12,
            color: Color(0xFF0077B6),
          ),
        ),
      ],
    );
  }
}

class _ExceptionsAndAuditLogsReport extends StatefulWidget {
  const _ExceptionsAndAuditLogsReport();

  @override
  State<_ExceptionsAndAuditLogsReport> createState() => _ExceptionsAndAuditLogsReportState();
}

class _ExceptionsAndAuditLogsReportState extends State<_ExceptionsAndAuditLogsReport> {
  String _searchQuery = '';
  late Stream<List<AttendanceCorrection>> _attendanceStream;
  late Stream<List<IncidentReport>> _incidentStream;

  @override
  void initState() {
    super.initState();
    _attendanceStream = FirebaseService.getAttendanceCorrections();
    _incidentStream = FirebaseService.getIncidentReports();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Search audit logs & exceptions...',
              hintStyle: const TextStyle(fontFamily: 'Lexend', color: Colors.grey),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF0077B6)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE4E9F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE4E9F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF03045E)),
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
          ),
          const SizedBox(height: 16),
          const Text(
            'Attendance Correction Audit Trail',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF03045E),
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<AttendanceCorrection>>(
            stream: _attendanceStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Error loading attendance corrections: ${snapshot.error}',
                    style: const TextStyle(fontFamily: 'Lexend', color: Colors.red),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF0077B6)));
              }
              final list = (snapshot.data ?? [])
                  .where((c) =>
                      c.reason.toLowerCase().contains(_searchQuery) ||
                      c.studentId.toLowerCase().contains(_searchQuery) ||
                      c.correctedBy.toLowerCase().contains(_searchQuery))
                  .toList();
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'No attendance corrections logged.',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      color: Color(0xFF0077B6),
                    ),
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final c = list[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    color: Colors.white,
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFF3E8FF),
                        child: Icon(Icons.edit_note, color: Colors.purple),
                      ),
                      title: Text(
                        'Student ID: ${c.studentId} (${c.oldEventType} ➔ ${c.newEventType})',
                        style: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600, color: Color(0xFF03045E)),
                      ),
                      subtitle: Text(
                        'Reason: ${c.reason}\nBy: ${c.correctedBy} at ${c.timestamp}',
                        style: const TextStyle(fontFamily: 'Lexend', color: Color(0xFF0077B6)),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Incident & Disruption Log',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF03045E),
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<IncidentReport>>(
            stream: _incidentStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Error loading incident reports: ${snapshot.error}',
                    style: const TextStyle(fontFamily: 'Lexend', color: Colors.red),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: Color(0xFF0077B6)));
              }
              final list = (snapshot.data ?? [])
                  .where((r) =>
                      r.category.toLowerCase().contains(_searchQuery) ||
                      r.description.toLowerCase().contains(_searchQuery) ||
                      r.busId.toLowerCase().contains(_searchQuery))
                  .toList();
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'No operational incident reports found.',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      color: Color(0xFF0077B6),
                    ),
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final r = list[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    color: Colors.white,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.orange.withValues(alpha: 0.15),
                        child: const Icon(Icons.warning_amber, color: Colors.orange),
                      ),
                      title: Text(
                        '[${r.severity}] ${r.category} (Bus: ${r.busId})',
                        style: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600, color: Color(0xFF03045E)),
                      ),
                      subtitle: Text(
                        '${r.description}\nDriver: ${r.driverId} at ${r.timestamp}',
                        style: const TextStyle(fontFamily: 'Lexend', color: Color(0xFF0077B6)),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}



