import 'dart:async';

import 'package:flutter/material.dart';
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
              const SizedBox(height: 16),

              // Quick Stats (when active)
              if (widget.activeSession != null) ...[
                _buildQuickStats(),
                const SizedBox(height: 16),
              ],

              // Control Buttons
              _buildBusSelector(),
              const SizedBox(height: 12),
              _buildControlButton(),
              const SizedBox(height: 12),

              // In-App Incident Reporting Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => _showIncidentReportDialog(),
                  icon: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                  ),
                  label: const Text(
                    'Report Incident / Delay',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      color: Colors.orange,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.orange, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

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
        gradient: LinearGradient(
          colors: isActive
              ? [const Color(0xFF4CAF50), const Color(0xFF45A049)]
              : [const Color(0xFF9E9E9E), const Color(0xFF757575)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isActive ? const Color(0xFF4CAF50) : Colors.grey)
                .withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
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
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                isActive ? 'ROUTE SESSION ACTIVE' : 'SESSION STOPPED',
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          if (_assignedBus != null) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white30),
            const SizedBox(height: 16),
            _buildStatusRow(
              Icons.directions_bus,
              'Bus',
              _assignedBus!.busNumber,
            ),
            const SizedBox(height: 8),
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
              const SizedBox(height: 8),
              _buildStatusRow(
                Icons.route,
                'Route',
                _assignedBus!.currentRoute!,
              ),
            ],
            if (isActive && _sessionStartTime != null) ...[
              const SizedBox(height: 8),
              _buildStatusRow(
                Icons.access_time,
                'Started',
                _formatTime(_sessionStartTime!),
              ),
              const SizedBox(height: 8),
              StreamBuilder(
                stream: Stream.periodic(const Duration(seconds: 1)),
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
              const SizedBox(height: 8),
              ValueListenableBuilder<int>(
                valueListenable: OfflineQueueService.pendingCountNotifier,
                builder: (context, pending, child) {
                  return _buildStatusRow(
                    pending > 0 ? Icons.cloud_off : Icons.cloud_done,
                    'Sync Status',
                    pending > 0 ? '$pending pending' : 'Synced',
                    colorOverride: pending > 0
                        ? Colors.orangeAccent
                        : Colors.greenAccent,
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
        Icon(icon, color: colorOverride ?? Colors.white70, size: 18),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14,
            color: Colors.white70,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorOverride ?? Colors.white,
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
                color: Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Center(
                child: Text(
                  'Select a bus to start',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
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
              baseColor: isActive ? Colors.red : const Color(0xFF0077B6),
              activeColor: isActive
                  ? Colors.redAccent
                  : const Color(0xFF00B4D8),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today\'s Bus',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF03045E),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: selectedValue,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            hint: const Text('Select assigned bus'),
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
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'You can choose any bus assigned to you before starting.',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12,
                  color: Color(0xFF0077B6),
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
        color: const Color(0xFF0077B6).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF0077B6).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF0077B6)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.activeSession != null
                  ? 'GPS tracking is active. All NFC scans are being recorded with location data. Switch to NFC tab to scan student cards.'
                  : 'Start your route session to begin GPS tracking and enable NFC card scanning.',
              style: const TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14,
                color: Color(0xFF0077B6),
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
          title: const Text('Log Incident / Disruption'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Category:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: category,
                  isExpanded: true,
                  items:
                      [
                            'Late Arrival',
                            'Route Disruption',
                            'Vehicle Breakdown',
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
                const SizedBox(height: 12),
                const Text(
                  'Severity:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Low', label: Text('Low')),
                    ButtonSegment(value: 'Medium', label: Text('Med')),
                    ButtonSegment(value: 'High', label: Text('High')),
                  ],
                  selected: {severity},
                  onSelectionChanged: (s) =>
                      setDlgState(() => severity = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description details...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final desc = descController.text.trim();
                if (desc.isEmpty) return;
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                final busId =
                    widget.activeSession?.busId ??
                    widget.selectedBusId ??
                    'unassigned';
                final report = IncidentReport(
                  id: '',
                  driverId: FirebaseService.currentUserId ?? 'driver',
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
                    const SnackBar(
                      content: Text('Incident report logged successfully.'),
                    ),
                  );
                }
              },

              child: const Text('Submit Report'),
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
    final eventsSnap = await swFirestore
        .collection('boarding_events')
        .where('sessionId', isEqualTo: sessionId)
        .get();

    final studentsSnap = await swFirestore
        .collection('students')
        .where('assignedBusId', isEqualTo: busId)
        .get();

    final boardEvents = eventsSnap.docs
        .where((e) => e['eventType'] == 'board')
        .length;
    final alightEvents = eventsSnap.docs
        .where((e) => e['eventType'] == 'alight')
        .length;

    final currentOnBoard = boardEvents - alightEvents;
    final totalStudents = studentsSnap.docs.length;
    final unboarded = totalStudents - boardEvents;

    if (!mounted) return;
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'End Trip Summary',
          style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (currentOnBoard > 0)
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.red.withValues(alpha: 0.1),
                child: Text(
                  'WARNING: $currentOnBoard student(s) are still marked as ON BOARD. Please ensure the bus is empty.',
                  style: const TextStyle(
                    color: Colors.red,
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
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    color: Colors.orange,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'Are you sure you want to end this trip?',
              style: TextStyle(fontFamily: 'Lexend'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Lexend')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'End Trip',
              style: TextStyle(fontFamily: 'Lexend', color: Colors.white),
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
          onError: (Object e, StackTrace st) {
            debugPrint('boarding_events listen: $e');
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
          onError: (Object e, StackTrace st) {
            debugPrint('students listen: $e');
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00B4D8).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart, color: Color(0xFF0077B6), size: 20),
              SizedBox(width: 8),
              Text(
                'Quick Stats',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF03045E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _quickStatRow(
            'Students Boarded Today',
            '$boardEvents/$totalStudents',
            Icons.person_add,
            const Color(0xFF4CAF50),
          ),
          const SizedBox(height: 12),
          _quickStatRow(
            'Currently On Bus',
            currentOnBoard.toString(),
            Icons.groups,
            const Color(0xFF0077B6),
          ),
          const SizedBox(height: 12),
          _quickStatRow(
            'Total Scans',
            events.length.toString(),
            Icons.qr_code_scanner,
            const Color(0xFF00B4D8),
          ),
          if (events.isNotEmpty) ...[
            const SizedBox(height: 12),
            _quickStatRow(
              'Last Scan',
              _lastScanLabel(events),
              Icons.update,
              const Color(0xFFFF9800),
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
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              color: Color(0xFF0077B6),
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF03045E),
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
