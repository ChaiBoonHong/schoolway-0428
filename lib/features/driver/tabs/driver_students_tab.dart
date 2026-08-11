import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:schoolway/core/widgets/app_modal_sheet.dart';
import 'package:schoolway/features/auth/firebase_error_handler.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/boarding_record_service.dart';
import 'package:schoolway/services/nfc_tag_reader.dart';
import 'package:schoolway/services/school_config_service.dart';
import 'package:url_launcher/url_launcher.dart';

class DriverStudentsTab extends StatefulWidget {
  final RouteSession? activeSession;

  const DriverStudentsTab({super.key, required this.activeSession});

  @override
  State<DriverStudentsTab> createState() => _DriverStudentsTabState();
}

class _DriverStudentsTabState extends State<DriverStudentsTab>
    with SingleTickerProviderStateMixin {
  late TabController _filterTabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _expandedStop;

  List<QueryDocumentSnapshot> _boardingEvents = [];
  StreamSubscription<QuerySnapshot>? _eventsSub;

  @override
  void initState() {
    super.initState();
    _filterTabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    _subscribeBoardingEvents();
  }

  @override
  void didUpdateWidget(covariant DriverStudentsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeSession?.id != widget.activeSession?.id) {
      _expandedStop = null;
      _subscribeBoardingEvents();
    }
  }

  void _subscribeBoardingEvents() {
    _eventsSub?.cancel();
    _eventsSub = null;

    final session = widget.activeSession;
    if (session == null) {
      setState(() => _boardingEvents = []);
      return;
    }

    _eventsSub = swFirestore
        .collection('boarding_events')
        .where('sessionId', isEqualTo: session.id)
        .snapshots()
        .listen(
          (snap) {
            if (mounted) setState(() => _boardingEvents = snap.docs);
          },
          onError: (Object error) {
            if (BoardingRecordService.isFirestoreWebSyncError(error)) {
              _eventsSub?.cancel();
              Future<void>.delayed(const Duration(seconds: 1), () {
                if (mounted) _subscribeBoardingEvents();
              });
            }
          },
        );
  }

  Future<void> _refreshBoardingEvents() async {
    final session = widget.activeSession;
    if (session == null) return;
    try {
      final snap = await swFirestore
          .collection('boarding_events')
          .where('sessionId', isEqualTo: session.id)
          .get();
      if (mounted) setState(() => _boardingEvents = snap.docs);
    } catch (_) {}
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _filterTabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activeSession == null) {
      return _buildInactiveView();
    }

    return SafeArea(
      bottom: false,
      child: ClipRect(
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search students...',
                  hintStyle: const TextStyle(fontFamily: 'Lexend'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(color: Color(0xFFE4E9F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(color: Color(0xFFE4E9F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(color: Color(0xFF03045E)),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),

            // Filter tabs
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _filterTabController,
                labelColor: const Color(0xFF0077B6),
                unselectedLabelColor: const Color(0xFF999999),
                indicatorColor: const Color(0xFF0077B6),
                labelStyle: const TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(text: 'All'),
                  Tab(text: 'On Board'),
                  Tab(text: 'Not Boarded'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _contactSchoolAdmin,
                  icon: const Icon(Icons.phone_in_talk),
                  label: const Text(
                    'Contact School Admin',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Student list
            Expanded(
              child: TabBarView(
                controller: _filterTabController,
                children: [
                  _buildStudentList(filter: 'all'),
                  _buildStudentList(filter: 'onboard'),
                  _buildStudentList(filter: 'notboarded'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentList({required String filter}) {
    return StreamBuilder<QuerySnapshot>(
      stream: swFirestore
          .collection('students')
          .where('assignedBusId', isEqualTo: widget.activeSession!.busId)
          .snapshots(),
      builder: (context, studentSnapshot) {
        if (!studentSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final students = studentSnapshot.data!.docs
            .map((doc) => Student.fromFirestore(doc))
            .toList();

        if (students.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_outline,
                  size: 80,
                  color: Colors.grey.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No students assigned',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 18,
                    color: Color(0xFF999999),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Contact admin to assign students to this bus',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14,
                    color: Color(0xFFCCCCCC),
                  ),
                ),
              ],
            ),
          );
        }

        final events = _boardingEvents;

        final filteredStudents = students.where((student) {
          if (_searchQuery.isNotEmpty) {
            final fullName = '${student.firstName} ${student.lastName}'
                .toLowerCase();
            final nfcCard = student.nfcCardId.toLowerCase();
            if (!fullName.contains(_searchQuery) &&
                !nfcCard.contains(_searchQuery)) {
              return false;
            }
          }

          final isOnBoard = _isStudentOnBoard(student.id, events);
          if (filter == 'onboard' && !isOnBoard) return false;
          if (filter == 'notboarded' && isOnBoard) return false;

          return true;
        }).toList();

        if (filteredStudents.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off,
                  size: 80,
                  color: Colors.grey.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  _searchQuery.isNotEmpty
                      ? 'No students found'
                      : 'No students in this category',
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 18,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ),
          );
        }

        final allByStop = <String, List<Student>>{};
        for (final student in students) {
          allByStop
              .putIfAbsent(_stopFor(student), () => <Student>[])
              .add(student);
        }
        final groupedStudents = <String, List<Student>>{};
        for (final student in filteredStudents) {
          groupedStudents
              .putIfAbsent(_stopFor(student), () => <Student>[])
              .add(student);
        }
        final sortedStops = groupedStudents.keys.toList()..sort(_compareStops);
        for (final stopStudents in groupedStudents.values) {
          stopStudents.sort((a, b) => a.fullName.compareTo(b.fullName));
        }
        String? firstWaitingStop;
        for (final stop in sortedStops) {
          if (allByStop[stop]!.any(
            (student) => _getLastEvent(student.id, events) == null,
          )) {
            firstWaitingStop = stop;
            break;
          }
        }
        firstWaitingStop ??= sortedStops.isEmpty ? null : sortedStops.first;
        final initialStop =
            _expandedStop != null && sortedStops.contains(_expandedStop)
            ? _expandedStop
            : firstWaitingStop;
        final directionLabel =
            widget.activeSession!.tripDirection == TripDirection.fromSchool
            ? 'Drop-off stops'
            : 'Pickup stops';

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                directionLabel,
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF03045E),
                ),
              ),
            ),
            ExpansionPanelList.radio(
              initialOpenPanelValue: initialStop,
              expansionCallback: (index, isExpanded) {
                setState(() {
                  _expandedStop = isExpanded ? null : sortedStops[index];
                });
              },
              children: [
                for (final stop in sortedStops)
                  ExpansionPanelRadio(
                    value: stop,
                    canTapOnHeader: true,
                    headerBuilder: (context, isExpanded) {
                      final allAtStop = allByStop[stop]!;
                      final onboard = allAtStop
                          .where((s) => _isStudentOnBoard(s.id, events))
                          .length;
                      final waiting = allAtStop
                          .where((s) => _getLastEvent(s.id, events) == null)
                          .length;
                      return ListTile(
                        leading: const Icon(
                          Icons.location_on,
                          color: Color(0xFF00B4D8),
                        ),
                        title: Text(
                          stop,
                          style: const TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          '${allAtStop.length} total · $waiting waiting · $onboard onboard',
                          style: const TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                    body: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Column(
                        children: groupedStudents[stop]!
                            .map((s) => _buildStudentCard(s, events))
                            .toList(),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildStudentCard(
    Student student,
    List<QueryDocumentSnapshot> events,
  ) {
    final isOnBoard = _isStudentOnBoard(student.id, events);
    final lastEvent = _getLastEvent(student.id, events);
    final statusColor = isOnBoard
        ? const Color(0xFF2E7D32)
        : lastEvent == null
        ? const Color(0xFF757575)
        : const Color(0xFFEF6C00);
    final statusText = isOnBoard
        ? 'ON BOARD'
        : lastEvent == null
        ? 'WAITING'
        : 'COMPLETED';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: statusColor.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            onTap: () => _showStudentDetails(student, lastEvent),
            leading: CircleAvatar(
              backgroundColor: statusColor.withValues(alpha: 0.12),
              child: Text(
                student.firstName.isEmpty
                    ? '?'
                    : student.firstName[0].toUpperCase(),
                style: TextStyle(color: statusColor),
              ),
            ),
            title: Text(
              student.fullName,
              style: const TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              lastEvent == null
                  ? 'No attendance event yet'
                  : _formatEventTime(lastEvent),
              style: const TextStyle(fontFamily: 'Lexend', fontSize: 12),
            ),
            trailing: Text(
              statusText,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showNFCScanDialog(student),
                  icon: const Icon(Icons.nfc, size: 18),
                  label: const Text('Scan NFC'),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => _showManualCheckInDialog(student, lastEvent),
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Manual'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showManualCheckInDialog(
    Student student,
    QueryDocumentSnapshot? lastEvent,
  ) {
    final isOnBoard =
        lastEvent != null &&
        BoardingRecordService.isBoardingEventType(
          lastEvent['eventType'] as String?,
        );
    final detailsController = TextEditingController();
    String? reason;
    String? error;
    var saving = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Manual Attendance: ${student.firstName} ${student.lastName}',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isOnBoard
                    ? 'Next action: Check out (alight)'
                    : 'Next action: Check in (board)',
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF03045E),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: reason,
                decoration: const InputDecoration(
                  labelText: 'Reason *',
                  border: OutlineInputBorder(),
                ),
                items: BoardingRecordService.manualReasons
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: saving
                    ? null
                    : (value) => setDialogState(() {
                        reason = value;
                        error = null;
                      }),
              ),
              const SizedBox(height: 8),
              if (reason == 'Other')
                TextField(
                  controller: detailsController,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'Details *',
                    border: OutlineInputBorder(),
                  ),
                ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final selected = reason;
                      if (selected == null) {
                        setDialogState(() => error = 'Select a reason.');
                        return;
                      }
                      try {
                        BoardingRecordService.manualReasonNote(
                          selected,
                          detailsController.text,
                        );
                      } on ArgumentError catch (e) {
                        setDialogState(() => error = e.message.toString());
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      final messenger = ScaffoldMessenger.of(context);
                      final session = widget.activeSession;
                      final driverId =
                          FirebaseAuth.instance.currentUser?.uid ?? 'driver';
                      if (session != null) {
                        try {
                          await BoardingRecordService.recordManualBoardingForStudent(
                            student: student,
                            session: session,
                            driverId: driverId,
                            reason: selected,
                            details: detailsController.text,
                            lastKnownEventType:
                                lastEvent?['eventType'] as String?,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Manual attendance recorded for ${student.firstName}.',
                                ),
                              ),
                            );
                            _refreshBoardingEvents();
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() {
                              saving = false;
                              error = 'Could not save attendance: $e';
                            });
                          }
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Event'),
            ),
          ],
        ),
      ),
    ).whenComplete(detailsController.dispose);
  }

  String _stopFor(Student student) {
    final raw = widget.activeSession!.tripDirection == TripDirection.fromSchool
        ? student.dropoffStop
        : student.pickupStop;
    final stop = raw?.trim() ?? '';
    return stop.isEmpty ? 'Unknown / Unassigned Stop' : stop;
  }

  int _compareStops(String a, String b) {
    const unknown = 'Unknown / Unassigned Stop';
    if (a == unknown) return 1;
    if (b == unknown) return -1;
    final numberPattern = RegExp(r'\d+');
    final aNumber = int.tryParse(numberPattern.firstMatch(a)?.group(0) ?? '');
    final bNumber = int.tryParse(numberPattern.firstMatch(b)?.group(0) ?? '');
    if (aNumber != null && bNumber != null) return aNumber.compareTo(bNumber);
    if (aNumber != null) return -1;
    if (bNumber != null) return 1;
    return a.compareTo(b);
  }

  Future<void> _contactSchoolAdmin() async {
    final phone = await SchoolConfigService.getAdminPhoneNumber();
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the phone app.')),
    );
  }

  Widget _buildInactiveView() {
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
                Icons.groups_outlined,
                size: 100,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Student List Unavailable',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Start a route session to view\nand manage student boarding',
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

  bool _isStudentOnBoard(String studentId, List<QueryDocumentSnapshot> events) {
    final studentEvents =
        events.where((e) => e['studentId'] == studentId).toList()..sort((a, b) {
          final aTime = (a['timestamp'] as Timestamp).toDate();
          final bTime = (b['timestamp'] as Timestamp).toDate();
          return bTime.compareTo(aTime);
        });

    if (studentEvents.isEmpty) return false;

    final lastEvent = studentEvents.first;
    return BoardingRecordService.isBoardingEventType(
      lastEvent['eventType'] as String?,
    );
  }

  QueryDocumentSnapshot? _getLastEvent(
    String studentId,
    List<QueryDocumentSnapshot> events,
  ) {
    final studentEvents =
        events.where((e) => e['studentId'] == studentId).toList()..sort((a, b) {
          final aTime = (a['timestamp'] as Timestamp).toDate();
          final bTime = (b['timestamp'] as Timestamp).toDate();
          return bTime.compareTo(aTime);
        });

    return studentEvents.isNotEmpty ? studentEvents.first : null;
  }

  String _formatEventTime(QueryDocumentSnapshot event) {
    final timestamp = (event['timestamp'] as Timestamp).toDate();
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final eventType = event['eventType'] as String?;
    final boarded = BoardingRecordService.isBoardingEventType(eventType);
    return '${boarded ? 'Boarded' : 'Dropped Off'} at $hour:$minute';
  }

  void _showStudentDetails(Student student, QueryDocumentSnapshot? lastEvent) {
    showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${student.firstName} ${student.lastName}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 12),
                _buildDetailRow('Student ID', student.id),
                _buildDetailRow('Assigned Stop', student.assignedStopName),
                if (student.nfcCardId.isNotEmpty)
                  _buildDetailRow('NFC Card ID', student.nfcCardId),
                if (lastEvent != null)
                  _buildDetailRow('Last Scan', _formatEventTime(lastEvent)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.privacy_tip_outlined,
                        color: Color(0xFF0077B6),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Parent contact hidden for privacy. Reach out to school admin for assistance.',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                            color: Color(0xFF03045E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontFamily: 'Lexend'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w600,
                color: Color(0xFF0077B6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'Lexend',
                color: Color(0xFF03045E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showNFCScanDialog(Student student) {
    final session = widget.activeSession;
    final driverId = FirebaseAuth.instance.currentUser?.uid;
    if (session == null || driverId == null) return;

    showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _StudentNfcScanSheet(
        student: student,
        session: session,
        driverId: driverId,
        onBoarded: _refreshBoardingEvents,
      ),
    );
  }
}

class _StudentNfcScanSheet extends StatefulWidget {
  final Student student;
  final RouteSession session;
  final String driverId;
  final VoidCallback? onBoarded;

  const _StudentNfcScanSheet({
    required this.student,
    required this.session,
    required this.driverId,
    this.onBoarded,
  });

  @override
  State<_StudentNfcScanSheet> createState() => _StudentNfcScanSheetState();
}

class _StudentNfcScanSheetState extends State<_StudentNfcScanSheet> {
  bool _busy = false;
  String? _error;
  bool _nfcReader = false;

  bool get _nfcOk =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startNfc());
  }

  @override
  void dispose() {
    unawaited(_stopNfc());
    super.dispose();
  }

  Future<void> _startNfc() async {
    if (!_nfcOk) return;
    try {
      final availability = await NfcManager.instance.checkAvailability();
      if (availability != NfcAvailability.enabled) return;
      _nfcReader = true;
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        onDiscovered: (tag) {
          unawaited(_onTag(tag));
        },
      );
    } catch (_) {
      _nfcReader = false;
    }
  }

  Future<void> _stopNfc() async {
    if (!_nfcReader) return;
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
    _nfcReader = false;
  }

  Future<void> _onTag(NfcTag tag) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.student.nfcCardId.isEmpty) {
        setState(() => _error = 'No NFC ID on file. Use manual record below.');
        return;
      }
      final raw = await readNfcTagIdentifier(tag);
      if (raw == null || raw.isEmpty) {
        setState(() => _error = 'Could not read card.');
        return;
      }
      if (!BoardingRecordService.nfcIdsMatch(
        widget.student.nfcCardId,
        BoardingRecordService.normalizeNfcKey(raw),
      )) {
        setState(() => _error = 'This card does not match this student.');
        return;
      }
      await BoardingRecordService.recordBoardingForStudent(
        student: widget.student,
        session: widget.session,
        driverId: widget.driverId,
      );
      widget.onBoarded?.call();
      if (!mounted) return;
      await _stopNfc();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recorded: ${widget.student.firstName} ${widget.student.lastName}',
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      setState(() => _error = _formatRecordError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatRecordError(Object e) {
    if (BoardingRecordService.isFirestoreWebSyncError(e)) {
      return 'Sync error – please try again.';
    }
    if (e is FirebaseException) {
      return FirebaseErrorHandler.getFirestoreErrorMessage(e);
    }
    return e.toString();
  }

  Future<void> _cancel() async {
    await _stopNfc();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.85;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Scan ${widget.student.firstName}\'s card',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 12),
                if (!_nfcOk)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'NFC is only available on Mobile devices. On web, use manual record.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: Color(0xFF0077B6),
                      ),
                    ),
                  ),
                const Icon(Icons.nfc, size: 64, color: Color(0xFF0077B6)),
                const SizedBox(height: 12),
                const Text(
                  'Hold the card near the device. Close this panel and use Manual if NFC is unavailable.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Lexend', fontSize: 14),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: Color(0xFF0077B6)),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      color: Colors.red,
                    ),
                  ),
                ],
                TextButton(
                  onPressed: _busy ? null : _cancel,
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontFamily: 'Lexend'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
