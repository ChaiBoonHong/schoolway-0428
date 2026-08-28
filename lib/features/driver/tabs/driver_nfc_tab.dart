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
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/boarding_record_service.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/services/nfc_tag_reader.dart';
import 'package:schoolway/services/offline_queue_service.dart';

class DriverNFCTab extends StatefulWidget {
  final RouteSession? activeSession;
  final bool nfcTabActive;
  final VoidCallback? onManualFallback;

  const DriverNFCTab({
    super.key,
    required this.activeSession,
    required this.nfcTabActive,
    this.onManualFallback,
  });

  @override
  State<DriverNFCTab> createState() => _DriverNFCTabState();
}

class _DriverNFCTabState extends State<DriverNFCTab>
    with SingleTickerProviderStateMixin {
  Bus? _assignedBus;
  String? _nfcHint;
  bool _nfcReaderActive = false;
  bool _handlingTag = false;
  StreamSubscription<List<BoardingEvent>>? _boardingEventsSub;
  StreamSubscription<QuerySnapshot>? _studentsSub;
  List<BoardingEvent> _boardingEvents = [];
  QuerySnapshot? _studentsSnap;
  List<BoardingEvent> _recentScans = [];

  StreamSubscription<QuerySnapshot>? _geofenceSub;
  int _visitedStopsCount = 0;
  int _totalStopsCount = 0;
  Map<String, dynamic>? _currentStopEvent;
  PlannedRoute? _plannedRoute;
  List<AssignedRouteStop> _assignedStops = const [];

  late final AnimationController _pulseController;

  bool get _nfcHardwareSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  String _cleanDisplayText(String value) {
    return value
        .replaceAll('�', '')
        .replaceAll('â€¢', '•')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _loadBusInfo();
    _syncHeaderStatsListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncNfcReader());
  }

  @override
  void didUpdateWidget(DriverNFCTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeSession?.id != widget.activeSession?.id) {
      _loadBusInfo();
      _syncHeaderStatsListeners();
    }
    if (oldWidget.nfcTabActive != widget.nfcTabActive ||
        oldWidget.activeSession?.id != widget.activeSession?.id) {
      _syncNfcReader();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _stopNfcReader();
    _boardingEventsSub?.cancel();
    _studentsSub?.cancel();
    _geofenceSub?.cancel();
    super.dispose();
  }

  void _syncHeaderStatsListeners() {
    _boardingEventsSub?.cancel();
    _studentsSub?.cancel();
    _geofenceSub?.cancel();
    _boardingEvents = [];
    _studentsSnap = null;
    _recentScans = [];
    _visitedStopsCount = 0;
    _totalStopsCount = 0;
    _currentStopEvent = null;
    _plannedRoute = null;
    _assignedStops = const [];

    final session = widget.activeSession;
    final driverUid = FirebaseAuth.instance.currentUser?.uid;
    if (session == null || driverUid == null) return;

    _boardingEventsSub =
        FirebaseService.watchDriverBoardingEvents(
          sessionId: session.id,
          driverUid: driverUid,
          newestFirst: true,
        ).listen(
          (events) {
            if (mounted) {
              setState(() {
                _boardingEvents = events;
                _recentScans = events.take(10).toList();
              });
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            AppLogger.error(
              'nfc',
              'NFC boarding event monitoring failed.',
              error: error,
              stackTrace: stackTrace,
            );
          },
        );

    _studentsSub = swFirestore
        .collection('students')
        .where('assignedBusId', isEqualTo: session.busId)
        .snapshots()
        .listen(
          (snapshot) {
            if (mounted) {
              setState(() {
                _studentsSnap = snapshot;
                _rebuildAssignedStops();
              });
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            AppLogger.error(
              'nfc',
              'NFC student monitoring failed.',
              error: error,
              stackTrace: stackTrace,
            );
          },
        );

    // Watch geofence events for unvisited stops badge
    _geofenceSub = swFirestore
        .collection('route_sessions')
        .doc(session.id)
        .collection('geofence_events')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen(
          (snap) {
            if (mounted) {
              setState(() {
                _visitedStopsCount = snap.docs
                    .where((doc) => doc.data()['type'] == 'at_stop')
                    .map((doc) => doc.data()['stopIndex'])
                    .toSet()
                    .length;
                final latest = snap.docs.isEmpty
                    ? null
                    : snap.docs.first.data();
                _currentStopEvent = latest?['type'] == 'at_stop'
                    ? latest
                    : null;
              });
            }
          },
          onError: (Object error, StackTrace stackTrace) => AppLogger.warning(
            'nfc',
            'Stop progress monitoring failed.',
            error: error,
            stackTrace: stackTrace,
          ),
        );

    if (session.routeId != null) {
      FirebaseService.getPlannedRouteById(session.routeId!).then((route) {
        if (mounted && route != null) {
          setState(() {
            _plannedRoute = route;
            _rebuildAssignedStops();
          });
        }
      });
    }
  }

  void _rebuildAssignedStops() {
    final route = _plannedRoute;
    final session = widget.activeSession;
    if (route == null || session == null) {
      _assignedStops = const [];
      _totalStopsCount = 0;
      return;
    }
    final students = (_studentsSnap?.docs ?? const <QueryDocumentSnapshot>[])
        .map(Student.fromFirestore)
        .toList();
    _assignedStops = buildAssignedRouteStops(
      route: route,
      busId: session.busId,
      direction: session.tripDirection,
      students: students,
      serviceStopRouteIndices: session.serviceStopRouteIndices,
    );
    _totalStopsCount = _assignedStops.length;
  }

  Future<void> _syncNfcReader() async {
    if (!_nfcHardwareSupported) {
      if (mounted && _nfcHint != null) setState(() => _nfcHint = null);
      return;
    }
    final shouldRun =
        widget.nfcTabActive && widget.activeSession != null && mounted;
    if (shouldRun) {
      await _startNfcReader();
    } else {
      await _stopNfcReader();
    }
  }

  Future<void> _startNfcReader() async {
    if (!_nfcHardwareSupported || _nfcReaderActive) return;
    try {
      final availability = await NfcManager.instance.checkAvailability();
      if (availability != NfcAvailability.enabled) {
        if (mounted) {
          setState(() {
            _nfcHint = availability == NfcAvailability.disabled
                ? 'Turn on NFC in device settings.'
                : 'NFC is not available on this device.';
          });
        }
        return;
      }
      if (mounted) setState(() => _nfcHint = null);
      _nfcReaderActive = true;
      await NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443},
        onDiscovered: (tag) {
          unawaited(_onTagDiscovered(tag));
        },
      );
    } catch (_) {
      _nfcReaderActive = false;
      if (mounted) setState(() => _nfcHint = 'Could not start NFC reader.');
    }
  }

  Future<void> _stopNfcReader() async {
    if (!_nfcReaderActive) return;
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
    _nfcReaderActive = false;
  }

  Future<void> _onTagDiscovered(NfcTag tag) async {
    if (_handlingTag || !mounted) return;
    final session = widget.activeSession;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (session == null || uid == null) return;

    _handlingTag = true;
    try {
      final scanned = await readNfcTagIdentifier(tag);
      if (scanned == null || scanned.isEmpty) {
        if (mounted) {
          HapticFeedback.vibrate();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).couldNotReadThisCardTryAgain,
                style: TextStyle(fontFamily: 'Lexend'),
              ),
            ),
          );
        }
        return;
      }

      final student = await BoardingRecordService.findStudentOnBusByNfc(
        scanned,
        session.busId,
      );
      if (student == null) {
        if (mounted) {
          HapticFeedback.vibrate();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).noStudentOnThisBusMatchesThis,
                style: TextStyle(fontFamily: 'Lexend'),
              ),
            ),
          );
        }
        return;
      }

      final result = await BoardingRecordService.recordBoardingForStudent(
        student: student,
        session: session,
        driverUid: uid,
      );

      if (mounted) {
        if (result.isQueued) {
          setState(() {
            _boardingEvents = [result.event, ..._boardingEvents];
            _recentScans = [result.event, ..._recentScans].take(10).toList();
          });
        }
        if (result.isDuplicate) {
          HapticFeedback.vibrate();
        } else {
          HapticFeedback.lightImpact();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.isDuplicate
                  ? AppLocalizations.of(
                      context,
                    ).duplicateNfcScanIgnored(student.firstName)
                  : result.isSynced
                  ? AppLocalizations.of(
                      context,
                    ).attendanceSavedForStudent(student.fullName)
                  : AppLocalizations.of(
                      context,
                    ).attendanceQueued(student.firstName),
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: result.isDuplicate
                ? SchoolWayTheme.warningDark
                : result.isSynced
                ? SchoolWayTheme.success
                : SchoolWayTheme.warningDark,
          ),
        );
      }
    } catch (error, stackTrace) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        final message = ErrorReporter.userMessage(
          context,
          error,
          stackTrace,
          category: 'boarding',
          message: 'NFC attendance failed.',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message, style: TextStyle(fontFamily: 'Lexend')),
            backgroundColor: SchoolWayTheme.danger,
          ),
        );
      }
    } finally {
      _handlingTag = false;
    }
  }

  Future<void> _loadBusInfo() async {
    if (widget.activeSession != null) {
      final bus = await FirebaseService.getBusById(widget.activeSession!.busId);
      if (mounted) setState(() => _assignedBus = bus);
    } else if (mounted) {
      setState(() => _assignedBus = null);
    }
  }

  int get _boardedCount {
    return _boardingEvents
        .where(
          (event) => BoardingRecordService.isBoardingEventType(event.eventType),
        )
        .length;
  }

  int get _dropOffCount {
    return _boardingEvents
        .where(
          (event) => BoardingRecordService.isDropOffEventType(event.eventType),
        )
        .length;
  }

  int get _totalAssignedStudents => _studentsSnap?.docs.length ?? 0;

  @override
  Widget build(BuildContext context) {
    if (widget.activeSession == null) return _buildInactiveView();

    return SafeArea(
      bottom: false,
      child: ClipRect(
        child: Column(
          children: [
            // Compact session header
            _buildSessionHeader(),

            if (_currentStopEvent != null) _buildCurrentStopCard(),

            // NFC hint if any
            if (_nfcHint != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: SchoolWayTheme.dangerSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: SchoolWayTheme.dangerDark,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _nfcHint!,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12,
                          color: SchoolWayTheme.dangerDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Offline Sync Banner
            ValueListenableBuilder<int>(
              valueListenable: OfflineQueueService.pendingCountNotifier,
              builder: (context, pendingCount, child) {
                if (pendingCount == 0) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: SchoolWayTheme.warning,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: SchoolWayTheme.warning),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off,
                        size: 18,
                        color: SchoolWayTheme.warningDark,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Offline: $pendingCount scans pending sync',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: SchoolWayTheme.warningDark,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      SizedBox(
                        height: 24,
                        child: ElevatedButton(
                          onPressed: () => OfflineQueueService.flushQueue(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SchoolWayTheme.warning,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: Text(
                            AppLocalizations.of(context).retry,
                            style: TextStyle(
                              fontSize: 11,
                              color: SchoolWayTheme.surface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // NFC scan area + Recent scans share remaining space
            Expanded(
              child: Column(
                children: [
                  Expanded(child: _buildScanArea()),
                  _buildRecentScansSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionHeader() {
    final busLabel = _assignedBus != null
        ? _cleanDisplayText(_assignedBus!.busNumber)
        : '...';
    final routeLabel = _assignedBus?.currentRoute != null
        ? _cleanDisplayText(_assignedBus!.currentRoute!)
        : 'No Route';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SchoolWayTheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, color: SchoolWayTheme.successBright, size: 10),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$busLabel  •  $routeLabel',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: SchoolWayTheme.surface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Text(
                  '$_boardedCount / $_totalAssignedStudents on board',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12,
                    color: SchoolWayTheme.surface70,
                  ),
                ),
              ],
            ),
          ),
          if (_totalStopsCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: SchoolWayTheme.warning,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_totalStopsCount - _visitedStopsCount} stops left',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: SchoolWayTheme.surface,
                ),
              ),
            ),
          // Live badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: SchoolWayTheme.surface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.nfc, color: SchoolWayTheme.surface, size: 14),
                SizedBox(width: 4),
                Text(
                  AppLocalizations.of(context).live,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: SchoolWayTheme.surface,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStopCard() {
    final stopIndex =
        (_currentStopEvent?['routeStopIndex'] as num?)?.toInt() ??
        (_currentStopEvent?['stopIndex'] as num?)?.toInt();
    AssignedRouteStop? currentStop;
    for (final stop in _assignedStops) {
      if (stop.routeStopIndex == stopIndex) {
        currentStop = stop;
        break;
      }
    }
    if (currentStop == null) return const SizedBox.shrink();

    final localizations = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      label:
          '${localizations.arrivedAtStop(currentStop.label)}. ${localizations.studentsExpected(currentStop.students.length)}',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SchoolWayTheme.infoSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SchoolWayTheme.info),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: SchoolWayTheme.info),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    localizations.arrivedAtStop(currentStop.label),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: SchoolWayTheme.navy,
                    ),
                  ),
                ),
                Text(
                  localizations.studentsExpected(currentStop.students.length),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: SchoolWayTheme.primary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            for (final student in currentStop.students)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                      _isStudentCurrentlyOnBoard(student.id)
                          ? Icons.check_circle
                          : Icons.schedule,
                      size: 18,
                      color: _isStudentCurrentlyOnBoard(student.id)
                          ? SchoolWayTheme.success
                          : SchoolWayTheme.warningDark,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        student.fullName,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          color: SchoolWayTheme.navy,
                        ),
                      ),
                    ),
                    Text(
                      _isStudentCurrentlyOnBoard(student.id)
                          ? localizations.onBoard
                          : localizations.waiting,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12,
                        color: _isStudentCurrentlyOnBoard(student.id)
                            ? SchoolWayTheme.success
                            : SchoolWayTheme.warningDark,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _isStudentCurrentlyOnBoard(String studentId) {
    final events =
        _boardingEvents.where((event) => event.studentId == studentId).toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (events.isEmpty) return false;
    return BoardingRecordService.isBoardingEventType(events.last.eventType);
  }

  Widget _buildScanArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final iconSize = (constraints.maxHeight * 0.42).clamp(80.0, 160.0);
        final nfcIconSize = iconSize * 0.5;

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale = 1.0 + _pulseController.value * 0.06;
                    final opacity = 0.08 + _pulseController.value * 0.12;
                    return Container(
                      width: iconSize,
                      height: iconSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: SchoolWayTheme.primary.withValues(
                          alpha: opacity,
                        ),
                      ),
                      child: Transform.scale(
                        scale: scale,
                        child: Icon(
                          Icons.nfc,
                          size: nfcIconSize,
                          color: SchoolWayTheme.primary,
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context).tapNfcCard,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: SchoolWayTheme.navy,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context).holdStudentCardNearDeviceToScan,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13,
                    color: SchoolWayTheme.blueGrey,
                  ),
                ),
                SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StatChip(
                      icon: Icons.login,
                      label: '$_boardedCount boarded',
                      color: SchoolWayTheme.successBright,
                    ),
                    SizedBox(width: 12),
                    _StatChip(
                      icon: Icons.logout,
                      label: '$_dropOffCount dropped off',
                      color: SchoolWayTheme.warning,
                    ),
                  ],
                ),
                SizedBox(height: 24),
                if (widget.onManualFallback != null)
                  OutlinedButton.icon(
                    onPressed: widget.onManualFallback,
                    icon: Icon(Icons.edit_note, size: 20),
                    label: Text(
                      AppLocalizations.of(context).manualOverride,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SchoolWayTheme.primary,
                      side: BorderSide(color: SchoolWayTheme.primary),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentScansSection() {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.28,
      ),
      decoration: BoxDecoration(
        color: SchoolWayTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: SchoolWayTheme.text12,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(Icons.history, color: SchoolWayTheme.primary, size: 18),
                SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context).recentScans,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: SchoolWayTheme.navy,
                  ),
                ),
                Spacer(),
                Text(
                  '${_boardingEvents.length} total',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12,
                    color: SchoolWayTheme.blueGrey,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 16),
          Expanded(
            child: _recentScans.isEmpty
                ? Center(
                    child: Text(
                      AppLocalizations.of(context).noScansYetTapAnNfcCard,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13,
                        color: SchoolWayTheme.blueGrey,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _recentScans.length,
                    itemBuilder: (context, index) {
                      return _buildScanRow(_recentScans[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanRow(BoardingEvent event) {
    final isBoarding = BoardingRecordService.isBoardingEventType(
      event.eventType,
    );
    final timeStr = _formatTime(event.timestamp);
    final color = !event.synced
        ? SchoolWayTheme.warning
        : isBoarding
        ? SchoolWayTheme.successBright
        : SchoolWayTheme.warning;

    return FutureBuilder<Student?>(
      future: FirebaseService.getStudentById(event.studentId),
      builder: (context, snapshot) {
        final name = snapshot.data != null
            ? '${snapshot.data!.firstName} ${snapshot.data!.lastName}'
            : 'Student';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isBoarding ? Icons.login : Icons.logout,
                  color: color,
                  size: 18,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: SchoolWayTheme.navy,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      !event.synced
                          ? '${isBoarding ? AppLocalizations.of(context).board2 : AppLocalizations.of(context).dropOff} · ${AppLocalizations.of(context).pendingSync}'
                          : isBoarding
                          ? AppLocalizations.of(context).board2
                          : AppLocalizations.of(context).dropOff,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 11,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                timeStr,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13,
                  color: SchoolWayTheme.blueGrey,
                ),
              ),
            ],
          ),
        );
      },
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
                Icons.nfc_outlined,
                size: 100,
                color: SchoolWayTheme.muted,
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: Text(
                AppLocalizations.of(context).nfcScanningDisabled,
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
                AppLocalizations.of(context).startARouteSessionFromTheTrip,
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

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
