import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:schoolway/core/widgets/slide_to_confirm.dart';
import 'package:schoolway/services/offline_queue_service.dart';

class DriverTripTab extends StatefulWidget {
  final RouteSession? activeSession;
  final VoidCallback onToggleSession;
  final bool isLoading;
  final List<Bus> assignedBuses;
  final String? selectedBusId;
  final ValueChanged<String?> onSelectBus;

  const DriverTripTab({
    super.key,
    required this.activeSession,
    required this.onToggleSession,
    required this.isLoading,
    required this.assignedBuses,
    required this.selectedBusId,
    required this.onSelectBus,
  });

  @override
  State<DriverTripTab> createState() => _DriverTripTabState();
}

class _DriverTripTabState extends State<DriverTripTab> {
  Bus? _assignedBus;
  DateTime? _sessionStartTime;
  PlannedRoute? _plannedRoute;
  Stream<PlannedRoute?>? _plannedRouteStream;
  String? _plannedRouteId;

  @override
  void initState() {
    super.initState();
    _loadBusInfo();
  }

  @override
  void didUpdateWidget(DriverTripTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeSession?.id != widget.activeSession?.id ||
        oldWidget.selectedBusId != widget.selectedBusId ||
        oldWidget.assignedBuses.length != widget.assignedBuses.length) {
      _loadBusInfo();
      _sessionStartTime = widget.activeSession?.startTime;
    }
  }

  Future<void> _loadBusInfo() async {
    if (widget.activeSession != null) {
      _watchPlannedRoute(widget.activeSession!.routeId);
      final bus = await FirebaseService.getBusById(widget.activeSession!.busId);
      if (mounted) {
        setState(() {
          _assignedBus = bus;
          _sessionStartTime = widget.activeSession!.startTime;
        });
      }
    } else {
      final selectedBusId = widget.selectedBusId;
      if (selectedBusId != null) {
        Bus? bus;
        for (final assigned in widget.assignedBuses) {
          if (assigned.id == selectedBusId) {
            bus = assigned;
            break;
          }
        }
        if (mounted) {
          _watchPlannedRoute(bus?.assignedRouteId);
          setState(() {
            _assignedBus = bus;
          });
        }
      } else if (mounted) {
        _watchPlannedRoute(null);
        setState(() {
          _assignedBus = null;
        });
      }
    }
  }

  void _watchPlannedRoute(String? routeId) {
    final id = routeId?.trim();
    if (_plannedRouteId == id) return;
    _plannedRouteId = id;
    _plannedRoute = null;
    _plannedRouteStream = id == null || id.isEmpty
        ? null
        : FirebaseService.watchPlannedRouteById(id);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ClipRect(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Session Status Card
              _buildSessionStatusCard(),
              SizedBox(height: 16),

              // Quick Stats (when active)
              if (widget.activeSession != null) ...[
                _buildQuickStats(),
                SizedBox(height: 16),
              ],

              // Control Buttons
              _buildBusSelector(),
              SizedBox(height: 12),
              _buildControlButton(),
              SizedBox(height: 12),

              // In-App Incident Reporting Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => _showIncidentReportDialog(),
                  icon: Icon(
                    Icons.warning_amber_rounded,
                    color: SchoolWayTheme.warning,
                  ),
                  label: Text(
                    AppLocalizations.of(context).reportIncidentDelay,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      color: SchoolWayTheme.warning,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: SchoolWayTheme.warning, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16),

              // Info Card
              _buildInfoCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionStatusCard() {
    final isActive = widget.activeSession != null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isActive ? SchoolWayTheme.success : SchoolWayTheme.mutedDark,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: (isActive ? SchoolWayTheme.success : SchoolWayTheme.muted)
                .withValues(alpha: 0.2),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isActive ? Icons.check_circle : Icons.radio_button_unchecked,
                color: SchoolWayTheme.surface,
                size: 24,
              ),
              SizedBox(width: 12),
              Flexible(
                child: Text(
                  isActive ? 'ROUTE SESSION ACTIVE' : 'SESSION STOPPED',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: SchoolWayTheme.surface,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          if (_assignedBus != null) ...[
            SizedBox(height: 16),
            Divider(color: SchoolWayTheme.surface30),
            SizedBox(height: 16),
            _buildStatusRow(
              Icons.directions_bus,
              'Bus',
              _assignedBus!.busNumber,
            ),
            SizedBox(height: 8),
            _buildStatusRow(
              Icons.credit_card,
              'License Plate',
              _assignedBus!.licensePlate,
            ),
            if (isActive && widget.activeSession?.routeId != null) ...[
              StreamBuilder<PlannedRoute?>(
                stream: _plannedRouteStream,
                initialData: _plannedRoute,
                builder: (context, snap) {
                  final route = snap.data ?? _plannedRoute;
                  if (route != null) _plannedRoute = route;
                  final title = route?.name ?? 'Loading...';
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildStatusRow(
                      Icons.alt_route,
                      'Planned route',
                      title,
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildStatusRow(
                  Icons.swap_calls,
                  'Trip direction',
                  widget.activeSession!.tripDirection ==
                          TripDirection.fromSchool
                      ? 'From school'
                      : 'To school',
                ),
              ),
            ] else if (_assignedBus!.currentRoute != null) ...[
              SizedBox(height: 8),
              _buildStatusRow(
                Icons.route,
                'Route',
                _assignedBus!.currentRoute!,
              ),
            ],
            if (isActive && _sessionStartTime != null) ...[
              SizedBox(height: 8),
              _buildStatusRow(
                Icons.access_time,
                'Started',
                _formatTime(_sessionStartTime!),
              ),
              SizedBox(height: 8),
              StreamBuilder(
                stream: Stream.periodic(Duration(seconds: 1)),
                builder: (context, snapshot) {
                  final duration = DateTime.now().difference(
                    _sessionStartTime!,
                  );
                  return _buildStatusRow(
                    Icons.timer,
                    'Duration',
                    _formatDuration(duration),
                  );
                },
              ),
              SizedBox(height: 8),
              ValueListenableBuilder<int>(
                valueListenable: OfflineQueueService.pendingCountNotifier,
                builder: (context, pending, child) {
                  return _buildStatusRow(
                    pending > 0 ? Icons.cloud_off : Icons.cloud_done,
                    'Sync Status',
                    pending > 0 ? '$pending pending' : 'Synced',
                    colorOverride: pending > 0
                        ? SchoolWayTheme.warning
                        : SchoolWayTheme.successBright,
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow(
    IconData icon,
    String label,
    String value, {
    Color? colorOverride,
  }) {
    return Row(
      children: [
        Icon(icon, color: colorOverride ?? SchoolWayTheme.surface70, size: 18),
        SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14,
            color: SchoolWayTheme.surface70,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorOverride ?? SchoolWayTheme.surface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats() {
    final s = widget.activeSession!;
    return _DriverTripQuickStats(
      key: ValueKey(s.id),
      sessionId: s.id,
      busId: s.busId,
    );
  }

  Widget _buildControlButton() {
    final isActive = widget.activeSession != null;
    Bus? selectedBus;
    final selectedBusId = widget.selectedBusId;
    if (selectedBusId != null) {
      for (final bus in widget.assignedBuses) {
        if (bus.id == selectedBusId) {
          selectedBus = bus;
          break;
        }
      }
    }
    final canResume =
        !isActive && (selectedBus?.status.toLowerCase() == 'active');
    final canStart = isActive || widget.selectedBusId != null;

    return SizedBox(
      height: 60,
      child: widget.isLoading || !canStart
          ? Container(
              decoration: BoxDecoration(
                color: SchoolWayTheme.muted.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  AppLocalizations.of(context).selectABusToStart,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: SchoolWayTheme.muted,
                  ),
                ),
              ),
            )
          : SlideToConfirm(
              text: isActive
                  ? 'Slide to End Trip'
                  : canResume
                  ? 'Slide to Resume Trip'
                  : 'Slide to Start Trip',
              baseColor: isActive
                  ? SchoolWayTheme.danger
                  : SchoolWayTheme.primary,
              activeColor: isActive
                  ? SchoolWayTheme.danger
                  : SchoolWayTheme.accent,
              onConfirm: () async {
                if (isActive) {
                  await _confirmEndTrip();
                } else {
                  widget.onToggleSession();
                }
              },
            ),
    );
  }

  Widget _buildBusSelector() {
    final isSessionActive = widget.activeSession != null;
    final selectedValue = widget.selectedBusId;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SchoolWayTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SchoolWayTheme.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).todaySBus,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SchoolWayTheme.navy,
            ),
          ),
          SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: selectedValue,
            isExpanded: true,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            hint: Text(AppLocalizations.of(context).selectAssignedBus),
            items: widget.assignedBuses
                .map(
                  (bus) => DropdownMenuItem<String>(
                    value: bus.id,
                    child: Text(
                      '${bus.busNumber} - ${bus.licensePlate} (${bus.status})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: isSessionActive ? null : widget.onSelectBus,
          ),
          if (!isSessionActive)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                AppLocalizations.of(context).youCanChooseAnyBusAssignedTo,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12,
                  color: SchoolWayTheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SchoolWayTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: SchoolWayTheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: SchoolWayTheme.primary),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.activeSession != null
                  ? 'GPS tracking is active. All NFC scans are being recorded with location data. Switch to NFC tab to scan student cards.'
                  : 'Start your route session to begin GPS tracking and enable NFC card scanning.',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14,
                color: SchoolWayTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  void _showIncidentReportDialog() {
    final descController = TextEditingController();
    String category = 'Late Arrival';
    String severity = 'Medium';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Text(AppLocalizations.of(context).logIncidentDisruption),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).category,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: category,
                  isExpanded: true,
                  items:
                      [
                            'Late Arrival',
                            'Route Disruption',
                            'Vehicle Issue',
                            'Student Absence',
                            'Weather Delay',
                            'Other',
                          ]
                          .map(
                            (c) => DropdownMenuItem(value: c, child: Text(c)),
                          )
                          .toList(),
                  onChanged: (val) {
                    if (val != null) setDlgState(() => category = val);
                  },
                ),
                SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context).severity,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'Low',
                      label: Text(AppLocalizations.of(context).low),
                    ),
                    ButtonSegment(
                      value: 'Medium',
                      label: Text(AppLocalizations.of(context).med),
                    ),
                    ButtonSegment(
                      value: 'High',
                      label: Text(AppLocalizations.of(context).high),
                    ),
                  ],
                  selected: {severity},
                  onSelectionChanged: (s) =>
                      setDlgState(() => severity = s.first),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).descriptionDetails,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                final desc = descController.text.trim();
                if (desc.isEmpty) return;
                final messenger = ScaffoldMessenger.of(context);
                final strings = AppLocalizations.of(context);
                Navigator.pop(ctx);
                final busId =
                    widget.activeSession?.busId ??
                    widget.selectedBusId ??
                    'unassigned';
                final report = IncidentReport(
                  id: '',
                  driverUid: FirebaseService.currentUserId ?? 'driver',
                  busId: busId,
                  sessionId: widget.activeSession?.id,
                  category: category,
                  description: desc,
                  severity: severity,
                  timestamp: DateTime.now(),
                );
                await FirebaseService.createIncidentReport(report);
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(strings.incidentReportLoggedSuccessfully),
                    ),
                  );
                }
              },

              child: Text(AppLocalizations.of(context).submitReport),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmEndTrip() async {
    if (widget.activeSession == null) return;
    final sessionId = widget.activeSession!.id;
    final busId = widget.activeSession!.busId;

    // Fetch students and boarding events to calculate unscanned
    final driverUid = FirebaseAuth.instance.currentUser?.uid;
    if (driverUid == null) return;
    final events = await FirebaseService.getDriverBoardingEvents(
      sessionId: sessionId,
      driverUid: driverUid,
    );

    final studentsSnap = await swFirestore
        .collection('students')
        .where('assignedBusId', isEqualTo: busId)
        .get();

    final boardEvents = events
        .where((event) => event.eventType == 'board')
        .length;
    final alightEvents = events
        .where((event) => event.eventType == 'alight')
        .length;

    final currentOnBoard = boardEvents - alightEvents;
    final totalStudents = studentsSnap.docs.length;
    final unboarded = totalStudents - boardEvents;

    if (!mounted) return;
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          AppLocalizations.of(context).endTripSummary,
          style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (currentOnBoard > 0)
                Container(
                  padding: const EdgeInsets.all(12),
                  color: SchoolWayTheme.danger.withValues(alpha: 0.1),
                  child: Text(
                    'WARNING: $currentOnBoard student(s) are still marked as ON BOARD. Please ensure the bus is empty.',
                    style: TextStyle(
                      color: SchoolWayTheme.danger,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Lexend',
                    ),
                  ),
                ),
              if (unboarded > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    '$unboarded student(s) did not board this trip.',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      color: SchoolWayTheme.warning,
                    ),
                  ),
                ),
              SizedBox(height: 16),
              Text(
                AppLocalizations.of(context).areYouSureYouWantToEnd,
                style: TextStyle(fontFamily: 'Lexend'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              AppLocalizations.of(context).cancel,
              style: TextStyle(fontFamily: 'Lexend'),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SchoolWayTheme.danger,
            ),
            child: Text(
              AppLocalizations.of(context).endTrip,
              style: TextStyle(
                fontFamily: 'Lexend',
                color: SchoolWayTheme.surface,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      widget.onToggleSession();
    }
  }
}

/// Parallel Firestore listeners (not nested [StreamBuilder]s) to reduce web
/// Firestore INTERNAL ASSERTION failures during session end / watch updates.
class _DriverTripQuickStats extends StatefulWidget {
  const _DriverTripQuickStats({
    super.key,
    required this.sessionId,
    required this.busId,
  });

  final String sessionId;
  final String busId;

  @override
  State<_DriverTripQuickStats> createState() => _DriverTripQuickStatsState();
}

class _DriverTripQuickStatsState extends State<_DriverTripQuickStats> {
  StreamSubscription<QuerySnapshot>? _eventsSub;
  StreamSubscription<QuerySnapshot>? _studentsSub;
  QuerySnapshot? _eventsSnap;
  QuerySnapshot? _studentsSnap;

  void _subscribe() {
    _eventsSub?.cancel();
    _studentsSub?.cancel();
    _eventsSub = swFirestore
        .collection('boarding_events')
        .where('sessionId', isEqualTo: widget.sessionId)
        .snapshots()
        .listen(
          (s) {
            if (mounted) setState(() => _eventsSnap = s);
          },
          onError: (Object error, StackTrace stackTrace) {
            AppLogger.error(
              'trips',
              'Boarding event monitoring failed.',
              error: error,
              stackTrace: stackTrace,
            );
          },
        );
    _studentsSub = swFirestore
        .collection('students')
        .where('assignedBusId', isEqualTo: widget.busId)
        .snapshots()
        .listen(
          (s) {
            if (mounted) setState(() => _studentsSnap = s);
          },
          onError: (Object error, StackTrace stackTrace) {
            AppLogger.error(
              'trips',
              'Trip student monitoring failed.',
              error: error,
              stackTrace: stackTrace,
            );
          },
        );
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(_DriverTripQuickStats oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.busId != widget.busId) {
      setState(() {
        _eventsSnap = null;
        _studentsSnap = null;
      });
      _subscribe();
    }
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _studentsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final events = _eventsSnap?.docs ?? [];
    final boardEvents = events.where((e) => e['eventType'] == 'board').length;
    final alightEvents = events.where((e) => e['eventType'] == 'alight').length;
    final currentOnBoard = boardEvents - alightEvents;
    final totalStudents = _studentsSnap?.docs.length ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SchoolWayTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SchoolWayTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart, color: SchoolWayTheme.primary, size: 20),
              SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).quickStats,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: SchoolWayTheme.navy,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          _quickStatRow(
            'Students Boarded Today',
            '$boardEvents/$totalStudents',
            Icons.person_add,
            SchoolWayTheme.successBright,
          ),
          SizedBox(height: 12),
          _quickStatRow(
            'Currently On Bus',
            currentOnBoard.toString(),
            Icons.groups,
            SchoolWayTheme.primary,
          ),
          SizedBox(height: 12),
          _quickStatRow(
            'Total Scans',
            events.length.toString(),
            Icons.qr_code_scanner,
            SchoolWayTheme.accent,
          ),
          if (events.isNotEmpty) ...[
            SizedBox(height: 12),
            _quickStatRow(
              'Last Scan',
              _lastScanLabel(events),
              Icons.update,
              SchoolWayTheme.warning,
            ),
          ],
        ],
      ),
    );
  }

  static Widget _quickStatRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              color: SchoolWayTheme.primary,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: SchoolWayTheme.navy,
          ),
        ),
      ],
    );
  }

  static String _lastScanLabel(List<QueryDocumentSnapshot> events) {
    if (events.isEmpty) return 'N/A';
    final lastEvent = events.first;
    final timestamp = (lastEvent['timestamp'] as Timestamp).toDate();
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
