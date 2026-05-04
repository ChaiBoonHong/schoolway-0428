import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/boarding_record_service.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/services/nfc_tag_reader.dart';

class DriverNFCTab extends StatefulWidget {
  final RouteSession? activeSession;
  final bool nfcTabActive;

  const DriverNFCTab({
    super.key,
    required this.activeSession,
    required this.nfcTabActive,
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
  StreamSubscription<QuerySnapshot>? _boardingEventsSub;
  StreamSubscription<QuerySnapshot>? _studentsSub;
  StreamSubscription<QuerySnapshot>? _recentScansSub;
  QuerySnapshot? _boardingEventsSnap;
  QuerySnapshot? _studentsSnap;
  List<BoardingEvent> _recentScans = const [];

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
      duration: const Duration(milliseconds: 1800),
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
    _recentScansSub?.cancel();
    super.dispose();
  }

  void _syncHeaderStatsListeners() {
    _boardingEventsSub?.cancel();
    _studentsSub?.cancel();
    _recentScansSub?.cancel();
    _boardingEventsSnap = null;
    _studentsSnap = null;
    _recentScans = const [];

    final session = widget.activeSession;
    if (session == null) return;

    _boardingEventsSub = swFirestore
        .collection('boarding_events')
        .where('sessionId', isEqualTo: session.id)
        .snapshots()
        .listen(
      (snapshot) {
        if (mounted) setState(() => _boardingEventsSnap = snapshot);
      },
      onError: (Object e, StackTrace st) {
        debugPrint('nfc header boarding_events listen: $e');
      },
    );

    _recentScansSub = swFirestore
        .collection('boarding_events')
        .where('sessionId', isEqualTo: session.id)
        .orderBy('timestamp', descending: true)
        .limit(10)
        .snapshots()
        .listen(
      (snapshot) {
        if (mounted) {
          setState(() {
            _recentScans = snapshot.docs
                .map((d) => BoardingEvent.fromFirestore(d))
                .toList();
          });
        }
      },
      onError: (Object e, StackTrace st) {
        debugPrint('nfc recent scans listen: $e');
      },
    );

    _studentsSub = swFirestore
        .collection('students')
        .where('assignedBusId', isEqualTo: session.busId)
        .snapshots()
        .listen(
      (snapshot) {
        if (mounted) setState(() => _studentsSnap = snapshot);
      },
      onError: (Object e, StackTrace st) {
        debugPrint('nfc header students listen: $e');
      },
    );
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
    } catch (_) {}
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not read this card. Try again.',
                  style: TextStyle(fontFamily: 'Lexend')),
            ),
          );
        }
        return;
      }

      final student = await BoardingRecordService.findStudentOnBusByNfc(
          scanned, session.busId);
      if (student == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No student on this bus matches this card.',
                  style: TextStyle(fontFamily: 'Lexend')),
            ),
          );
        }
        return;
      }

      await BoardingRecordService.recordBoardingForStudent(
        student: student,
        session: session,
        driverId: uid,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved: ${student.firstName} ${student.lastName}',
              style: const TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = BoardingRecordService.isFirestoreWebSyncError(e)
            ? 'Sync error – please try again.'
            : 'Could not save record: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(msg, style: const TextStyle(fontFamily: 'Lexend')),
            backgroundColor: Colors.red,
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
    final docs = _boardingEventsSnap?.docs ?? const [];
    return docs
        .where((d) => BoardingRecordService.isBoardingEventType(
            d['eventType'] as String?))
        .length;
  }

  int get _dropOffCount {
    final docs = _boardingEventsSnap?.docs ?? const [];
    return docs
        .where((d) =>
            !BoardingRecordService.isBoardingEventType(
                d['eventType'] as String?) &&
            d['eventType'] != null)
        .length;
  }

  int get _totalAssignedStudents => _studentsSnap?.docs.length ?? 0;

  @override
  Widget build(BuildContext context) {
    if (widget.activeSession == null) return _buildInactiveView();

    return SafeArea(
      child: Column(
        children: [
          // Compact session header
          _buildSessionHeader(),

          // NFC hint if any
          if (_nfcHint != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 18, color: Color(0xFFB71C1C)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _nfcHint!,
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12,
                        color: Color(0xFFB71C1C),
                      ),
                    ),
                  ),
                ],
              ),
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
        gradient: const LinearGradient(
          colors: [Color(0xFF0077B6), Color(0xFF00B4D8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, color: Colors.greenAccent, size: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$busLabel  •  $routeLabel',
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$_boardedCount / $_totalAssignedStudents on board',
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          // Live badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.nfc, color: Colors.white, size: 14),
                SizedBox(width: 4),
                Text(
                  'LIVE',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
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
                        color: const Color(0xFF0077B6)
                            .withValues(alpha: opacity),
                      ),
                      child: Transform.scale(
                        scale: scale,
                        child: Icon(
                          Icons.nfc,
                          size: nfcIconSize,
                          color: const Color(0xFF0077B6),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'TAP NFC CARD',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF03045E),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hold student card near device to scan',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13,
                    color: Colors.blueGrey.shade500,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StatChip(
                      icon: Icons.login,
                      label: '$_boardedCount boarded',
                      color: const Color(0xFF4CAF50),
                    ),
                    const SizedBox(width: 12),
                    _StatChip(
                      icon: Icons.logout,
                      label: '$_dropOffCount dropped off',
                      color: const Color(0xFFFF9800),
                    ),
                  ],
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
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
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
                const Icon(Icons.history, color: Color(0xFF0077B6), size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Recent Scans',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF03045E),
                  ),
                ),
                const Spacer(),
                Text(
                  '${(_boardingEventsSnap?.docs.length ?? 0)} total',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12,
                    color: Colors.blueGrey.shade400,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: _recentScans.isEmpty
                ? Center(
                    child: Text(
                      'No scans yet — tap an NFC card to begin',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13,
                        color: Colors.blueGrey.shade300,
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
    final isBoarding =
        BoardingRecordService.isBoardingEventType(event.eventType);
    final timeStr = _formatTime(event.timestamp);
    final color = isBoarding ? const Color(0xFF4CAF50) : const Color(0xFFFF9800);

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
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isBoarding ? Icons.login : Icons.logout,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF03045E),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      isBoarding ? 'Boarded' : 'Dropped Off',
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
                  color: Colors.blueGrey.shade400,
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
                Icons.nfc_outlined,
                size: 100,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'NFC Scanning Disabled',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Start a route session from the Trip tab\nto enable NFC card scanning',
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
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
