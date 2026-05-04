import 'dart:async';

import 'package:flutter/material.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:schoolway/core/schoolway_firestore.dart';

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
          setState(() {
            _assignedBus = bus;
          });
        }
      } else if (mounted) {
        setState(() {
          _assignedBus = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
            const SizedBox(height: 16),

            // Info Card
            _buildInfoCard(),
          ],
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
              FutureBuilder<PlannedRoute?>(
                future: FirebaseService.getPlannedRouteById(
                  widget.activeSession!.routeId!,
                ),
                builder: (context, snap) {
                  final title = snap.connectionState == ConnectionState.waiting
                      ? 'Loading...'
                      : snap.data?.name ?? 'Unknown route';
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
                  final duration = DateTime.now().difference(_sessionStartTime!);
                  return _buildStatusRow(
                    Icons.timer,
                    'Duration',
                    _formatDuration(duration),
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
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
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
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
    final canResume = !isActive && (selectedBus?.status.toLowerCase() == 'active');
    final canStart = isActive || widget.selectedBusId != null;

    return SizedBox(
      height: 64,
      child: ElevatedButton(
        onPressed: widget.isLoading || !canStart ? null : widget.onToggleSession,
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive ? Colors.red : const Color(0xFF0077B6),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
        ),
        child: widget.isLoading
            ? const SizedBox(
                height: 28,
                width: 28,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isActive
                        ? Icons.stop_circle
                        : canResume
                            ? Icons.playlist_play
                            : Icons.play_circle,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isActive
                        ? 'End Route Session'
                        : canResume
                            ? 'Resume Route Session'
                            : 'Start Route Session',
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
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
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          const Icon(
            Icons.info_outline,
            color: Color(0xFF0077B6),
          ),
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
    final boardEvents =
        events.where((e) => e['eventType'] == 'board').length;
    final alightEvents =
        events.where((e) => e['eventType'] == 'alight').length;
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

