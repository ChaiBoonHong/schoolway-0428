import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
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
    start: DateTime.now().subtract(Duration(days: 6)),
    end: DateTime.now(),
  );

  bool get _usesDatePicker =>
      widget.reportType == 'daily' ||
      widget.reportType == 'bus_activity' ||
      widget.reportType == 'driver_activity';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(_getReportTitle()),
        actions: [
          if (_usesDatePicker)
            IconButton(
              icon: Icon(Icons.calendar_today),
              tooltip: AppLocalizations.of(context).chooseDate,
              onPressed: () async {
                if (widget.reportType == 'bus_activity' ||
                    widget.reportType == 'driver_activity') {
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
        return Center(
          child: Text(
            AppLocalizations.of(context).unknownReportType,
            style: TextStyle(fontFamily: 'Lexend', color: SchoolWayTheme.navy),
          ),
        );
    }
  }
}

/// Computes [startInclusive, endExclusive) based on the given DateTimeRange.
(DateTime startInclusive, DateTime endExclusive) _dateRangeWindow(
  DateTimeRange range,
) {
  final startInclusive = DateTime(
    range.start.year,
    range.start.month,
    range.start.day,
  );
  final endExclusive = DateTime(
    range.end.year,
    range.end.month,
    range.end.day,
  ).add(Duration(days: 1));
  return (startInclusive, endExclusive);
}

Future<Map<String, String>> _resolveDriverLabels(
  Iterable<String> driverUids,
) async {
  final out = <String, String>{};
  for (final id in driverUids.toSet()) {
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
        return SchoolWayTheme.success;
      case _DayAttendanceStatus.alight:
        return SchoolWayTheme.warning;
      case _DayAttendanceStatus.absent:
        return SchoolWayTheme.muted;
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
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            color: SchoolWayTheme.navy,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sortedDayEvents.isEmpty)
                Text(
                  AppLocalizations.of(context).noBusActionsRecordedOnThisDate,
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
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: SchoolWayTheme.primary,
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
            child: Text(
              AppLocalizations.of(context).close,
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
    final endOfDay = startOfDay.add(Duration(days: 1));

    return StreamBuilder<QuerySnapshot>(
      stream: swFirestore
          .collection('boarding_events')
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .where('timestamp', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('timestamp', descending: false)
          .snapshots(),
      builder: (context, eventSnap) {
        if (eventSnap.hasError) {
          return Center(
            child: Text(
              'Error: ${eventSnap.error}',
              style: TextStyle(
                fontFamily: 'Lexend',
                color: SchoolWayTheme.navy,
              ),
            ),
          );
        }

        if (eventSnap.connectionState == ConnectionState.waiting &&
            !eventSnap.hasData) {
          return Center(
            child: CircularProgressIndicator(color: SchoolWayTheme.primary),
          );
        }

        return StreamBuilder<List<Student>>(
          stream: FirebaseService.getAllStudents(),
          builder: (context, studentSnap) {
            if (studentSnap.hasError) {
              return Center(
                child: Text(
                  'Error: ${studentSnap.error}',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    color: SchoolWayTheme.navy,
                  ),
                ),
              );
            }

            if (studentSnap.connectionState == ConnectionState.waiting &&
                !studentSnap.hasData) {
              return Center(
                child: CircularProgressIndicator(color: SchoolWayTheme.primary),
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
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: SchoolWayTheme.navy,
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
                              color: _statusColor(
                                status,
                              ).withValues(alpha: 0.5),
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
                  iconColor: SchoolWayTheme.primary,
                  collapsedIconColor: SchoolWayTheme.primary,
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  title: Text(
                    classLabel,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: SchoolWayTheme.navy,
                    ),
                  ),
                  subtitle: Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13,
                      color: SchoolWayTheme.primary,
                    ),
                  ),
                  children: [
                    if (students.isEmpty)
                      Padding(
                        padding: EdgeInsets.only(bottom: 8, left: 4, right: 4),
                        child: Text(
                          AppLocalizations.of(context).noStudentsInThisClass,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            color: SchoolWayTheme.primary,
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
              SizedBox(height: 16),
              _dailyClassFilterDropdown(),
              if (_classFilter != null) ...[
                SizedBox(height: 8),
                Text(
                  'Showing class $_classFilter only',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13,
                    color: SchoolWayTheme.primary,
                  ),
                ),
              ],
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      title: 'Board',
                      value: board.toString(),
                      icon: Icons.login,
                      color: SchoolWayTheme.success,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Drop Off',
                      value: alight.toString(),
                      icon: Icons.logout,
                      color: SchoolWayTheme.warning,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Absent',
                      value: absent.toString(),
                      icon: Icons.person_off_outlined,
                      color: SchoolWayTheme.muted,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                AppLocalizations.of(context).attendanceByClass,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: SchoolWayTheme.navy,
                ),
              ),
              SizedBox(height: 4),
              Text(
                AppLocalizations.of(context).tapAClassToExpandTheRoster,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13,
                  color: SchoolWayTheme.primary,
                ),
              ),
            ];

            if (_classFilter != null) {
              final students = _studentsInClass(allStudents, _classFilter!);
              bodyChildren.add(
                buildClassSection(
                  _classFilter!,
                  'Class $_classFilter',
                  students,
                ),
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
                  buildClassSection(
                    'unassigned',
                    'Unassigned class',
                    unassigned,
                  ),
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
        color: SchoolWayTheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today, color: SchoolWayTheme.surface, size: 32),
          SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context).reportDate,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  color: SchoolWayTheme.surface70,
                  fontSize: 14,
                ),
              ),
              Text(
                DateFormat('EEEE, MMMM d, y').format(date),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  color: SchoolWayTheme.surface,
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
      color: SchoolWayTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text(
              AppLocalizations.of(context).schoolClass,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w600,
                color: SchoolWayTheme.navy,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String?>(
                value: _classFilter,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                hint: Text(
                  AppLocalizations.of(context).allClasses,
                  style: TextStyle(fontFamily: 'Lexend'),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      AppLocalizations.of(context).allClasses,
                      style: TextStyle(fontFamily: 'Lexend'),
                    ),
                  ),
                  ...kSchoolClassIds.map(
                    (c) => DropdownMenuItem<String?>(
                      value: c,
                      child: Text(c, style: TextStyle(fontFamily: 'Lexend')),
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
        if (busSnap.connectionState == ConnectionState.waiting &&
            !busSnap.hasData) {
          return Center(
            child: CircularProgressIndicator(color: SchoolWayTheme.primary),
          );
        }
        final buses = busSnap.data ?? [];

        return StreamBuilder<QuerySnapshot>(
          stream: swFirestore
              .collection('boarding_events')
              .where(
                'timestamp',
                isGreaterThanOrEqualTo: Timestamp.fromDate(start),
              )
              .where('timestamp', isLessThan: Timestamp.fromDate(end))
              .snapshots(),
          builder: (context, eventSnap) {
            if (eventSnap.hasError) {
              return Center(
                child: Text(
                  'Error: ${eventSnap.error}',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    color: SchoolWayTheme.navy,
                  ),
                ),
              );
            }
            if (eventSnap.connectionState == ConnectionState.waiting &&
                !eventSnap.hasData) {
              return Center(
                child: CircularProgressIndicator(color: SchoolWayTheme.primary),
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
                    color: SchoolWayTheme.primary,
                    icon: Icons.date_range,
                  ),
                  SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context).nfcBoardAndDropOffCountsPer,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13,
                      color: SchoolWayTheme.primary,
                    ),
                  ),
                  SizedBox(height: 20),
                  if (buses.isEmpty)
                    Text(
                      AppLocalizations.of(context).noBusesRegistered,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: SchoolWayTheme.primary,
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
                                        ? SchoolWayTheme.success
                                        : SchoolWayTheme.muted,
                                    size: 28,
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          bus.busNumber,
                                          style: TextStyle(
                                            fontFamily: 'Lexend',
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: SchoolWayTheme.navy,
                                          ),
                                        ),
                                        Text(
                                          bus.currentRoute ??
                                              'No route assigned',
                                          style: TextStyle(
                                            fontFamily: 'Lexend',
                                            fontSize: 13,
                                            color: SchoolWayTheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _StatItem(
                                    label: AppLocalizations.of(context).board2,
                                    value: b.toString(),
                                    color: SchoolWayTheme.success,
                                  ),
                                  _StatItem(
                                    label: AppLocalizations.of(context).dropOff,
                                    value: a.toString(),
                                    color: SchoolWayTheme.warning,
                                  ),
                                  _StatItem(
                                    label: AppLocalizations.of(context).total,
                                    value: t.toString(),
                                    color: SchoolWayTheme.primary,
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
              style: TextStyle(
                fontFamily: 'Lexend',
                color: SchoolWayTheme.navy,
              ),
            ),
          );
        }
        if (eventSnap.connectionState == ConnectionState.waiting &&
            !eventSnap.hasData) {
          return Center(
            child: CircularProgressIndicator(color: SchoolWayTheme.primary),
          );
        }

        final board = <String, int>{};
        final alight = <String, int>{};
        final total = <String, int>{};

        for (final doc in eventSnap.data?.docs ?? []) {
          final data = doc.data() as Map<String, dynamic>;
          final driverUid = data['driverUid'] as String? ?? '';
          if (driverUid.isEmpty) continue;
          _accumulateEventCounts(data, board, alight, total, driverUid);
        }

        final driverUids = total.keys.toList()
          ..sort((a, b) => (total[b] ?? 0).compareTo(total[a] ?? 0));

        return FutureBuilder<Map<String, String>>(
          future: _resolveDriverLabels(driverUids),
          builder: (context, nameSnap) {
            if (nameSnap.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator(color: SchoolWayTheme.primary),
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
                    color: SchoolWayTheme.accent,
                    icon: Icons.badge_outlined,
                  ),
                  SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(
                      context,
                    ).countsOfNfcScansRecordedUnderEach,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13,
                      color: SchoolWayTheme.primary,
                    ),
                  ),
                  SizedBox(height: 20),
                  if (driverUids.isEmpty)
                    Text(
                      AppLocalizations.of(
                        context,
                      ).noDriverAttributedScansInThisPeriod,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: SchoolWayTheme.primary,
                      ),
                    )
                  else
                    ...driverUids.map((id) {
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
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: SchoolWayTheme.navy,
                                ),
                              ),
                              SizedBox(height: 10),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _StatItem(
                                    label: AppLocalizations.of(context).board2,
                                    value: b.toString(),
                                    color: SchoolWayTheme.success,
                                  ),
                                  _StatItem(
                                    label: AppLocalizations.of(context).dropOff,
                                    value: a.toString(),
                                    color: SchoolWayTheme.warning,
                                  ),
                                  _StatItem(
                                    label: AppLocalizations.of(context).total,
                                    value: t.toString(),
                                    color: SchoolWayTheme.primary,
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
                style: TextStyle(
                  fontFamily: 'Lexend',
                  color: SchoolWayTheme.navy,
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Center(
            child: CircularProgressIndicator(color: SchoolWayTheme.primary),
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
                color: SchoolWayTheme.danger,
                icon: Icons.emergency_outlined,
              ),
              SizedBox(height: 8),
              Text(
                AppLocalizations.of(
                  context,
                ).driverTriggeredEmergenciesResolveActiveItemsFrom,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13,
                  color: SchoolWayTheme.primary,
                ),
              ),
              SizedBox(height: 16),
              if (docs.isEmpty)
                Text(
                  AppLocalizations.of(context).noEmergencyAlertsRecorded,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    color: SchoolWayTheme.primary,
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
                            ? SchoolWayTheme.danger.withValues(alpha: 0.15)
                            : SchoolWayTheme.muted.withValues(alpha: 0.15),
                        child: Icon(
                          Icons.emergency,
                          color: active
                              ? SchoolWayTheme.danger
                              : SchoolWayTheme.muted,
                        ),
                      ),
                      title: Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(alert.timestamp),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          color: SchoolWayTheme.navy,
                        ),
                      ),
                      subtitle: Text(
                        'Bus ${alert.busId}\n'
                        '${alert.status}'
                        '${alert.resolvedAt != null ? ' · ${DateFormat('yyyy-MM-dd HH:mm').format(alert.resolvedAt!)}' : ''}',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          color: SchoolWayTheme.primary,
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
          Icon(icon, color: SchoolWayTheme.surface, size: 30),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    color: SchoolWayTheme.surface70,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    color: SchoolWayTheme.surface,
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
        color: SchoolWayTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          SizedBox(height: 8),
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
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12,
              color: SchoolWayTheme.primary,
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
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 12,
            color: SchoolWayTheme.primary,
          ),
        ),
      ],
    );
  }
}

class _ExceptionsAndAuditLogsReport extends StatefulWidget {
  const _ExceptionsAndAuditLogsReport();

  @override
  State<_ExceptionsAndAuditLogsReport> createState() =>
      _ExceptionsAndAuditLogsReportState();
}

class _ExceptionsAndAuditLogsReportState
    extends State<_ExceptionsAndAuditLogsReport> {
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
              hintText: AppLocalizations.of(context).searchAuditLogsExceptions,
              hintStyle: TextStyle(
                fontFamily: 'Lexend',
                color: SchoolWayTheme.muted,
              ),
              prefixIcon: Icon(Icons.search, color: SchoolWayTheme.primary),
              filled: true,
              fillColor: SchoolWayTheme.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: SchoolWayTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: SchoolWayTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: SchoolWayTheme.navy),
              ),
            ),
            onChanged: (val) =>
                setState(() => _searchQuery = val.toLowerCase()),
          ),
          SizedBox(height: 16),
          Text(
            AppLocalizations.of(context).attendanceCorrectionAuditTrail,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: SchoolWayTheme.navy,
            ),
          ),
          SizedBox(height: 8),
          StreamBuilder<List<AttendanceCorrection>>(
            stream: _attendanceStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Error loading attendance corrections: ${snapshot.error}',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      color: SchoolWayTheme.danger,
                    ),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return Center(
                  child: CircularProgressIndicator(
                    color: SchoolWayTheme.primary,
                  ),
                );
              }
              final list = (snapshot.data ?? [])
                  .where(
                    (c) =>
                        c.reason.toLowerCase().contains(_searchQuery) ||
                        c.studentId.toLowerCase().contains(_searchQuery) ||
                        c.correctedBy.toLowerCase().contains(_searchQuery),
                  )
                  .toList();
              if (list.isEmpty) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    AppLocalizations.of(context).noAttendanceCorrectionsLogged,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      color: SchoolWayTheme.primary,
                    ),
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final c = list[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                    color: SchoolWayTheme.surface,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: SchoolWayTheme.purpleSurface,
                        child: Icon(
                          Icons.edit_note,
                          color: SchoolWayTheme.purple,
                        ),
                      ),
                      title: Text(
                        'Student ID: ${c.studentId} (${c.oldEventType} ➔ ${c.newEventType})',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          color: SchoolWayTheme.navy,
                        ),
                      ),
                      subtitle: Text(
                        'Reason: ${c.reason}\nBy: ${c.correctedBy} at ${c.timestamp}',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          color: SchoolWayTheme.primary,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          SizedBox(height: 24),
          Text(
            AppLocalizations.of(context).incidentDisruptionLog,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: SchoolWayTheme.navy,
            ),
          ),
          SizedBox(height: 8),
          StreamBuilder<List<IncidentReport>>(
            stream: _incidentStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Error loading incident reports: ${snapshot.error}',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      color: SchoolWayTheme.danger,
                    ),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return Center(
                  child: CircularProgressIndicator(
                    color: SchoolWayTheme.primary,
                  ),
                );
              }
              final list = (snapshot.data ?? [])
                  .where(
                    (r) =>
                        r.category.toLowerCase().contains(_searchQuery) ||
                        r.description.toLowerCase().contains(_searchQuery) ||
                        r.busId.toLowerCase().contains(_searchQuery),
                  )
                  .toList();
              if (list.isEmpty) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    AppLocalizations.of(
                      context,
                    ).noOperationalIncidentReportsFound,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      color: SchoolWayTheme.primary,
                    ),
                  ),
                );
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final r = list[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                    color: SchoolWayTheme.surface,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: SchoolWayTheme.warning.withValues(
                          alpha: 0.15,
                        ),
                        child: Icon(
                          Icons.warning_amber,
                          color: SchoolWayTheme.warning,
                        ),
                      ),
                      title: Text(
                        '[${r.severity}] ${r.category} (Bus: ${r.busId})',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          color: SchoolWayTheme.navy,
                        ),
                      ),
                      subtitle: Text(
                        '${r.description}\nDriver: ${r.driverUid} at ${r.timestamp}',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          color: SchoolWayTheme.primary,
                        ),
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
