import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'package:schoolway/core/diagnostics/error_reporter.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:schoolway/core/widgets/app_modal_sheet.dart';
import 'package:schoolway/core/widgets/schoolway_components.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/boarding_record_service.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/services/nfc_tag_reader.dart';
import 'package:schoolway/services/offline_queue_service.dart';
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

  List<BoardingEvent> _boardingEvents = [];
  List<BoardingEvent> _pendingEvents = [];
  StreamSubscription<List<BoardingEvent>>? _eventsSub;

  @override
  void initState() {
    super.initState();
    _filterTabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
    OfflineQueueService.pendingCountNotifier.addListener(_refreshPendingEvents);
    _subscribeBoardingEvents();
    _refreshPendingEvents();
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

    final driverUid = FirebaseAuth.instance.currentUser?.uid;
    if (driverUid == null) return;

    _eventsSub =
        FirebaseService.watchDriverBoardingEvents(
          sessionId: session.id,
          driverUid: driverUid,
        ).listen(
          (events) {
            if (mounted) setState(() => _boardingEvents = events);
          },
          onError: (Object error, StackTrace stackTrace) {
            AppLogger.warning(
              'boarding',
              'Boarding event monitoring failed.',
              error: error,
              stackTrace: stackTrace,
            );
            if (BoardingRecordService.isFirestoreWebSyncError(error)) {
              _eventsSub?.cancel();
              Future<void>.delayed(Duration(seconds: 1), () {
                if (mounted) _subscribeBoardingEvents();
              });
            }
          },
        );
  }

  Future<void> _refreshBoardingEvents() async {
    final session = widget.activeSession;
    final driverUid = FirebaseAuth.instance.currentUser?.uid;
    if (session == null || driverUid == null) return;
    try {
      final events = await FirebaseService.getDriverBoardingEvents(
        sessionId: session.id,
        driverUid: driverUid,
      );
      if (mounted) setState(() => _boardingEvents = events);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'data',
        'Malformed or unavailable optional data was ignored.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _refreshPendingEvents() {
    final session = widget.activeSession;
    final driverUid = FirebaseAuth.instance.currentUser?.uid;
    if (session == null || driverUid == null) {
      if (mounted) setState(() => _pendingEvents = []);
      return;
    }
    final pending = OfflineQueueService.pendingBoardingEvents(
      sessionId: session.id,
      driverUid: driverUid,
    );
    if (mounted) setState(() => _pendingEvents = pending);
  }

  List<BoardingEvent> get _visibleBoardingEvents {
    final syncedIds = _boardingEvents.map((event) => event.id).toSet();
    return [
      ..._boardingEvents,
      ..._pendingEvents.where((event) => !syncedIds.contains(event.id)),
    ];
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    OfflineQueueService.pendingCountNotifier.removeListener(
      _refreshPendingEvents,
    );
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).searchStudents,
                  hintStyle: TextStyle(fontFamily: 'Lexend'),
                  prefixIcon: Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
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
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(SchoolWayTheme.radiusLarge),
              ),
              child: TabBar(
                controller: _filterTabController,
                labelColor: SchoolWayTheme.primary,
                unselectedLabelColor: SchoolWayTheme.disabled,
                indicatorColor: SchoolWayTheme.primary,
                labelStyle: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                tabs: [
                  Tab(text: AppLocalizations.of(context).allStudents),
                  Tab(text: AppLocalizations.of(context).onBoard),
                  Tab(text: AppLocalizations.of(context).notBoarded),
                ],
              ),
            ),

            SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _contactSchoolAdmin,
                  icon: Icon(Icons.phone_in_talk),
                  label: Text(
                    AppLocalizations.of(context).contactSchoolAdmin,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(height: 12),

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
          return Center(child: CircularProgressIndicator());
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
                  color: SchoolWayTheme.muted.withValues(alpha: 0.5),
                ),
                SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context).noStudentsAssigned,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 18,
                    color: SchoolWayTheme.disabled,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  AppLocalizations.of(
                    context,
                  ).contactAdminToAssignStudentsToThis,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14,
                    color: SchoolWayTheme.neutralDivider,
                  ),
                ),
              ],
            ),
          );
        }

        final events = _visibleBoardingEvents;

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
                  color: SchoolWayTheme.muted.withValues(alpha: 0.5),
                ),
                SizedBox(height: 16),
                Text(
                  _searchQuery.isNotEmpty
                      ? AppLocalizations.of(context).noStudentsFound
                      : AppLocalizations.of(context).noStudentsInCategory,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 18,
                    color: SchoolWayTheme.disabled,
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
            ? AppLocalizations.of(context).dropoffStops
            : AppLocalizations.of(context).pickupStops;

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                directionLabel,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: SchoolWayTheme.navy,
                ),
              ),
            ),
            for (final stop in sortedStops) ...[
              Builder(
                builder: (context) {
                  final allAtStop = allByStop[stop]!;
                  final onboard = allAtStop
                      .where((student) => _isStudentOnBoard(student.id, events))
                      .length;
                  final waiting = allAtStop
                      .where(
                        (student) => _getLastEvent(student.id, events) == null,
                      )
                      .length;
                  final completed = allAtStop.length - waiting - onboard;
                  final expanded = (_expandedStop ?? initialStop) == stop;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(
                        SchoolWayTheme.radiusLarge,
                      ),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Column(
                      children: [
                        Semantics(
                          button: true,
                          expanded: expanded,
                          label: stop,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              SchoolWayTheme.radiusLarge,
                            ),
                            onTap: () => setState(
                              () => _expandedStop = expanded ? '' : stop,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(
                                        SchoolWayTheme.radius,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.location_on_outlined,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          stop,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          ).attendanceStopSummary(
                                            allAtStop.length,
                                            waiting,
                                            onboard,
                                            completed,
                                          ),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    expanded
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (expanded)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Column(
                              children: groupedStudents[stop]!
                                  .map(
                                    (student) =>
                                        _buildStudentCard(student, events),
                                  )
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
            SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildStudentCard(Student student, List<BoardingEvent> events) {
    final isOnBoard = _isStudentOnBoard(student.id, events);
    final lastEvent = _getLastEvent(student.id, events);
    final isPending = lastEvent != null && !lastEvent.synced;
    final statusColor = isPending
        ? SchoolWayTheme.warning
        : isOnBoard
        ? SchoolWayTheme.success
        : lastEvent == null
        ? SchoolWayTheme.mutedDark
        : SchoolWayTheme.warningDark;
    final statusText = isPending
        ? AppLocalizations.of(context).pendingSync
        : isOnBoard
        ? AppLocalizations.of(context).onBoard
        : lastEvent == null
        ? AppLocalizations.of(context).waiting
        : AppLocalizations.of(context).completed;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(SchoolWayTheme.radiusLarge),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(SchoolWayTheme.radiusLarge),
        onTap: () => _showStudentDetails(student, lastEvent),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: statusColor.withValues(alpha: 0.12),
                    child: Text(
                      student.firstName.isEmpty
                          ? '?'
                          : student.firstName[0].toUpperCase(),
                      style: TextStyle(color: statusColor),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.fullName,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        SizedBox(height: 4),
                        Text(
                          lastEvent == null
                              ? AppLocalizations.of(
                                  context,
                                ).noAttendanceEventYet
                              : _formatEventTime(lastEvent),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        SizedBox(height: 8),
                        SchoolWayStatusBadge(
                          label: statusText,
                          status: isPending
                              ? SchoolWayStatus.warning
                              : isOnBoard
                              ? SchoolWayStatus.success
                              : lastEvent == null
                              ? SchoolWayStatus.info
                              : SchoolWayStatus.warning,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _showManualCheckInDialog(student, lastEvent),
                  icon: Icon(Icons.edit_note_outlined, size: 18),
                  label: Text(AppLocalizations.of(context).correctAttendance),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showManualCheckInDialog(Student student, BoardingEvent? lastEvent) {
    final isOnBoard =
        lastEvent != null &&
        BoardingRecordService.isBoardingEventType(lastEvent.eventType);
    final detailsController = TextEditingController();
    String? reason;
    String? error;
    var saving = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            AppLocalizations.of(
              context,
            ).manualAttendanceTitle(student.fullName),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isOnBoard
                      ? AppLocalizations.of(context).nextActionCheckOut
                      : AppLocalizations.of(context).nextActionCheckIn,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    color: SchoolWayTheme.navy,
                  ),
                ),
                SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).reason,
                    border: OutlineInputBorder(),
                  ),
                  items: BoardingRecordService.manualReasons
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_manualReasonLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) => setDialogState(() {
                          reason = value;
                          error = null;
                        }),
                ),
                SizedBox(height: 8),
                if (reason == 'Other')
                  TextField(
                    controller: detailsController,
                    enabled: !saving,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).details,
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (error != null) ...[
                  SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: SchoolWayTheme.danger)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final selected = reason;
                      if (selected == null) {
                        setDialogState(
                          () =>
                              error = AppLocalizations.of(context).selectReason,
                        );
                        return;
                      }
                      try {
                        BoardingRecordService.manualReasonNote(
                          selected,
                          detailsController.text,
                        );
                      } on ArgumentError {
                        setDialogState(
                          () => error = AppLocalizations.of(
                            context,
                          ).validationError,
                        );
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      final localizations = AppLocalizations.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      final session = widget.activeSession;
                      final driverUid = FirebaseAuth.instance.currentUser?.uid;
                      if (session == null || driverUid == null) {
                        setDialogState(() {
                          saving = false;
                          error = localizations.authenticationError;
                        });
                        return;
                      }
                      {
                        try {
                          final result =
                              await BoardingRecordService.recordManualBoardingForStudent(
                                student: student,
                                session: session,
                                driverUid: driverUid,
                                reason: selected,
                                details: detailsController.text,
                                lastKnownEventType: lastEvent?.eventType,
                              );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  result.isSynced
                                      ? localizations.attendanceSaved(
                                          student.firstName,
                                        )
                                      : localizations.attendanceQueued(
                                          student.firstName,
                                        ),
                                ),
                                backgroundColor: result.isSynced
                                    ? SchoolWayTheme.success
                                    : SchoolWayTheme.warningDark,
                              ),
                            );
                            if (result.isSynced) _refreshBoardingEvents();
                          }
                        } catch (exception, stackTrace) {
                          if (ctx.mounted) {
                            setDialogState(() {
                              saving = false;
                              error = ErrorReporter.userMessage(
                                ctx,
                                exception,
                                stackTrace,
                                category: 'boarding',
                                message: 'Manual attendance failed.',
                              );
                            });
                          }
                        }
                      }
                    },
              child: saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(AppLocalizations.of(context).saveEvent),
            ),
          ],
        ),
      ),
    ).whenComplete(detailsController.dispose);
  }

  String _manualReasonLabel(String reason) => switch (reason) {
    'Card forgotten' => AppLocalizations.of(context).cardForgotten,
    'Card unreadable' => AppLocalizations.of(context).cardUnreadable,
    'NFC unavailable' => AppLocalizations.of(context).nfcUnavailable,
    'Admin instruction' => AppLocalizations.of(context).adminInstruction,
    _ => AppLocalizations.of(context).other,
  };

  String _stopFor(Student student) {
    final session = widget.activeSession!;
    final routeStopIndex = studentStopIndex(student, session.tripDirection);
    if (routeStopIndex != null) {
      final tripOrderIndex = session.serviceStopRouteIndices.indexOf(
        routeStopIndex,
      );
      if (tripOrderIndex >= 0) return 'Stop ${tripOrderIndex + 1}';
    }
    return AppLocalizations.of(context).unknownUnassignedStop;
  }

  int _compareStops(String a, String b) {
    final unknown = AppLocalizations.of(context).unknownUnassignedStop;
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
      SnackBar(
        content: Text(AppLocalizations.of(context).couldNotOpenThePhoneApp),
      ),
    );
  }

  Widget _buildInactiveView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: SchoolWayTheme.muted.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.groups_outlined,
                size: 100,
                color: SchoolWayTheme.muted,
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: Text(
                AppLocalizations.of(context).studentListUnavailable,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: SchoolWayTheme.muted,
                ),
              ),
            ),
            SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: Text(
                AppLocalizations.of(context).startARouteSessionToViewAnd,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 16,
                  color: SchoolWayTheme.primary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isStudentOnBoard(String studentId, List<BoardingEvent> events) {
    final studentEvents =
        events.where((event) => event.studentId == studentId).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (studentEvents.isEmpty) return false;

    final lastEvent = studentEvents.first;
    return BoardingRecordService.isBoardingEventType(lastEvent.eventType);
  }

  BoardingEvent? _getLastEvent(String studentId, List<BoardingEvent> events) {
    final studentEvents =
        events.where((event) => event.studentId == studentId).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return studentEvents.isNotEmpty ? studentEvents.first : null;
  }

  String _formatEventTime(BoardingEvent event) {
    final timestamp = event.timestamp;
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final boarded = BoardingRecordService.isBoardingEventType(event.eventType);
    final time = '$hour:$minute';
    return boarded
        ? AppLocalizations.of(context).boardedAt(time)
        : AppLocalizations.of(context).droppedOffAt(time);
  }

  void _showStudentDetails(Student student, BoardingEvent? lastEvent) {
    showAppModalSheet<void>(
      context: context,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: SchoolWayTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${student.firstName} ${student.lastName}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                  ),
                ),
                SizedBox(height: 12),
                _buildDetailRow('Student ID', student.id),
                _buildDetailRow('Assigned Stop', _stopFor(student)),
                if (student.nfcCardId.isNotEmpty)
                  _buildDetailRow('NFC Card ID', student.nfcCardId),
                if (lastEvent != null)
                  _buildDetailRow('Last Scan', _formatEventTime(lastEvent)),
                SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SchoolWayTheme.info,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: SchoolWayTheme.info),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.privacy_tip_outlined,
                        color: SchoolWayTheme.primary,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(
                            context,
                          ).parentContactHiddenForPrivacyReachOut,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                            color: SchoolWayTheme.navy,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12),
                if (student.nfcCardId.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showNFCScanDialog(student);
                    },
                    icon: Icon(Icons.nfc),
                    label: Text(AppLocalizations.of(context).scanNfc),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    AppLocalizations.of(context).close,
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
                color: SchoolWayTheme.primary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Lexend',
                color: SchoolWayTheme.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showNFCScanDialog(Student student) {
    final session = widget.activeSession;
    final driverUid = FirebaseAuth.instance.currentUser?.uid;
    if (session == null || driverUid == null) return;

    showAppModalSheet<void>(
      context: context,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (context) => _StudentNfcScanSheet(
        student: student,
        session: session,
        driverUid: driverUid,
        onBoarded: _refreshBoardingEvents,
      ),
    );
  }
}

class _StudentNfcScanSheet extends StatefulWidget {
  final Student student;
  final RouteSession session;
  final String driverUid;
  final VoidCallback? onBoarded;

  const _StudentNfcScanSheet({
    required this.student,
    required this.session,
    required this.driverUid,
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
    } catch (error, stackTrace) {
      AppLogger.warning(
        'data',
        'Malformed or unavailable optional data was ignored.',
        error: error,
        stackTrace: stackTrace,
      );
    }
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
      final result = await BoardingRecordService.recordBoardingForStudent(
        student: widget.student,
        session: widget.session,
        driverUid: widget.driverUid,
      );
      widget.onBoarded?.call();
      if (!mounted) return;
      await _stopNfc();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isSynced
                ? AppLocalizations.of(
                    context,
                  ).attendanceSavedForStudent(widget.student.fullName)
                : AppLocalizations.of(
                    context,
                  ).attendanceQueued(widget.student.firstName),
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: result.isSynced
              ? SchoolWayTheme.success
              : SchoolWayTheme.warningDark,
        ),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(
        () => _error = ErrorReporter.userMessage(
          context,
          error,
          stackTrace,
          category: 'boarding',
          message: 'Manual boarding record failed.',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            color: SchoolWayTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Scan ${widget.student.firstName}\'s card',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                SizedBox(height: 12),
                if (!_nfcOk)
                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      AppLocalizations.of(
                        context,
                      ).nfcIsOnlyAvailableOnMobileDevices,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: SchoolWayTheme.primary,
                      ),
                    ),
                  ),
                Icon(Icons.nfc, size: 64, color: SchoolWayTheme.primary),
                SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context).holdTheCardNearTheDeviceClose,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Lexend', fontSize: 14),
                ),
                if (_busy)
                  Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(
                      color: SchoolWayTheme.primary,
                    ),
                  ),
                if (_error != null) ...[
                  SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      color: SchoolWayTheme.danger,
                    ),
                  ),
                ],
                TextButton(
                  onPressed: _busy ? null : _cancel,
                  child: Text(
                    AppLocalizations.of(context).cancel,
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
