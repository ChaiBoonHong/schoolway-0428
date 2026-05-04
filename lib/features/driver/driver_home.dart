import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/services/location_service.dart';
import 'package:schoolway/core/widgets/app_modal_sheet.dart';
import 'package:schoolway/features/driver/tabs/driver_nfc_tab.dart';
import 'package:schoolway/features/driver/tabs/driver_map_tab.dart';
import 'package:schoolway/features/driver/tabs/driver_trip_tab.dart';
import 'package:schoolway/features/driver/tabs/driver_students_tab.dart';
import 'package:schoolway/features/shell/shared_profile_tab.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  static const routeName = '/driver';

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  RouteSession? _activeSession;
  List<Bus> _assignedBuses = const [];
  String? _selectedBusId;
  bool _isLoading = false;
  int _currentTabIndex = 0;
  StreamSubscription<QuerySnapshot>? _assignedBusesSubscription;

  @override
  void initState() {
    super.initState();
    _startAssignedBusesListener();
    _checkActiveSession();
  }

  @override
  void dispose() {
    _assignedBusesSubscription?.cancel();
    super.dispose();
  }

  /// Ensures child widgets (e.g. Trip tab Firestore listeners) are disposed before
  /// the next async work — avoids Firestore web "INTERNAL ASSERTION" on watch pipeline.
  Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  void _startAssignedBusesListener() {
    if (_currentUserId == null) return;
    _assignedBusesSubscription?.cancel();
    _assignedBusesSubscription = FirebaseService.busesCollection
        .where('currentDriverId', isEqualTo: _currentUserId)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final buses = snapshot.docs.map(Bus.fromFirestore).toList()
        ..sort((a, b) => a.busNumber.compareTo(b.busNumber));
      setState(() {
        _assignedBuses = buses;
        if (_activeSession != null) {
          _selectedBusId = _activeSession!.busId;
        } else if (_selectedBusId == null ||
            !_assignedBuses.any((bus) => bus.id == _selectedBusId)) {
          _selectedBusId = _assignedBuses.isNotEmpty ? _assignedBuses.first.id : null;
        }
      });
    });
  }

  Future<void> _loadAssignedBuses() async {
    if (_currentUserId == null) return;

    final assignedBusSnapshot = await FirebaseService.busesCollection
        .where('currentDriverId', isEqualTo: _currentUserId)
        .get();
    final buses = assignedBusSnapshot.docs.map(Bus.fromFirestore).toList()
      ..sort((a, b) => a.busNumber.compareTo(b.busNumber));

    if (!mounted) return;
    setState(() {
      _assignedBuses = buses;
      if (_activeSession != null) {
        _selectedBusId = _activeSession!.busId;
      } else if (_selectedBusId == null ||
          !_assignedBuses.any((bus) => bus.id == _selectedBusId)) {
        _selectedBusId = _assignedBuses.isNotEmpty ? _assignedBuses.first.id : null;
      }
    });
  }

  Future<void> _checkActiveSession() async {
    if (_currentUserId == null) return;

    await _loadAssignedBuses();

    final existingDriverSession =
        await FirebaseService.getActiveSessionForDriver(_currentUserId);
    if (existingDriverSession != null) {
      if (!mounted) return;
      setState(() {
        _activeSession = existingDriverSession;
        _selectedBusId = existingDriverSession.busId;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _activeSession = null;
      if (_selectedBusId == null && _assignedBuses.isNotEmpty) {
        _selectedBusId = _assignedBuses.first.id;
      }
    });
  }

  void _onSelectBus(String? busId) {
    if (_activeSession != null) return;
    setState(() {
      _selectedBusId = busId;
    });
  }

  Future<Bus> _resolveSelectedBus() async {
    if (_assignedBuses.isEmpty) {
      throw Exception('No bus assigned to you. Please contact admin.');
    }

    final busId = _selectedBusId ?? _assignedBuses.first.id;
    return _assignedBuses.firstWhere(
      (bus) => bus.id == busId,
      orElse: () => _assignedBuses.first,
    );
  }

  /// Shown only when creating a new session (not when resuming).
  Future<TripDirection?> _pickTripDirection() async {
    return showAppModalSheet<TripDirection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Trip direction',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: Color(0xFF03045E),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Map pins and route order follow your choice.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.pop(ctx, TripDirection.toSchool),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF03045E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      'To school',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(ctx, TripDirection.fromSchool),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF03045E),
                      side: const BorderSide(color: Color(0xFF03045E)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      'From school',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
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

  Future<void> _startOrResumeSession(Bus bus) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return;

    if (bus.status.toLowerCase() == 'active') {
      final existingSession = await FirebaseService.getActiveSessionForBus(bus.id);
      if (existingSession != null && existingSession.driverId == currentUserId) {
        setState(() {
          _activeSession = existingSession;
          _selectedBusId = bus.id;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Resumed your active route session.',
                style: TextStyle(fontFamily: 'Lexend'),
              ),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Admin manually set bus to Active without a session yet.
      if (existingSession == null) {
        final tripDirection = await _pickTripDirection();
        if (!mounted || tripDirection == null) return;
        final sessionId = await FirebaseService.startRouteSession(
          driverId: currentUserId,
          busId: bus.id,
          routeId: bus.assignedRouteId,
          tripDirection: tripDirection,
        );
        final sessionDoc =
            await FirebaseService.routeSessionsCollection.doc(sessionId).get();
        setState(() {
          _activeSession = RouteSession.fromFirestore(sessionDoc);
          _selectedBusId = bus.id;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Route session started from active bus assignment.',
                style: TextStyle(fontFamily: 'Lexend'),
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      throw Exception('Assigned bus is currently "Active" under another driver.');
    }

    if (bus.status.toLowerCase() != 'idle') {
      throw Exception('Assigned bus is currently "${bus.status}". Please contact admin.');
    }

    final tripDirection = await _pickTripDirection();
    if (!mounted || tripDirection == null) return;

    final sessionId = await FirebaseService.startRouteSession(
      driverId: currentUserId,
      busId: bus.id,
      routeId: bus.assignedRouteId,
      tripDirection: tripDirection,
    );
    final sessionDoc =
        await FirebaseService.routeSessionsCollection.doc(sessionId).get();

    setState(() {
      _activeSession = RouteSession.fromFirestore(sessionDoc);
      _selectedBusId = bus.id;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Route session started. Ready to scan NFC cards.',
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleRouteSession() async {
    if (_currentUserId == null) return;
    
    setState(() => _isLoading = true);

    try {
      if (_activeSession == null) {
        await _loadAssignedBuses();
        final bus = await _resolveSelectedBus();
        await _startOrResumeSession(bus);
      } else {
        final onBoardCount = await _studentsOnBoardCount(_activeSession!);
        if (onBoardCount > 0) {
          if (mounted) {
            await showAppModalSheet<void>(
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
                        const Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFFF9800), size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          'Cannot End Trip',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '$onBoardCount student${onBoardCount == 1 ? ' is' : 's are'} still on board.\n'
                          'All students must be dropped off before ending the route session.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14,
                            color: Color(0xFF03045E),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0077B6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('OK',
                              style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return;
        }

        // End route: clear local session first so Trip/Map listeners unmount before
        // Firestore writes (fixes web Firestore watch assertion with nested streams).
        final sessionId = _activeSession!.id;
        final uid = _currentUserId;
        setState(() {
          _activeSession = null;
        });
        await _waitForNextFrame();
        try {
          await FirebaseService.endRouteSession(sessionId);
        } catch (e) {
          final recovered =
              await FirebaseService.getActiveSessionForDriver(uid);
          if (mounted &&
              recovered != null &&
              recovered.id == sessionId) {
            setState(() => _activeSession = recovered);
          }
          rethrow;
        }
        await _loadAssignedBuses();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Route session ended. Data synced.',
                style: TextStyle(fontFamily: 'Lexend'),
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: $e',
              style: const TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<int> _studentsOnBoardCount(RouteSession session) async {
    final snap = await swFirestore
        .collection('boarding_events')
        .where('sessionId', isEqualTo: session.id)
        .get();

    final lastByStudent = <String, String>{};
    final sorted = snap.docs.toList()
      ..sort((a, b) {
        final aT = (a['timestamp'] as Timestamp).toDate();
        final bT = (b['timestamp'] as Timestamp).toDate();
        return aT.compareTo(bT);
      });
    for (final doc in sorted) {
      lastByStudent[doc['studentId'] as String] =
          doc['eventType'] as String? ?? '';
    }

    return lastByStudent.values
        .where((t) => t == 'board' || t == 'boarded')
        .length;
  }

  Future<void> _onEmergencyPressed() async {
    if (_currentUserId == null || _activeSession == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please start a route session first',
            style: TextStyle(fontFamily: 'Lexend'),
          ),
        ),
      );
      return;
    }

    // Show confirmation dialog first
    final confirmed = await showAppModalSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Emergency Alert', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 24)),
                const SizedBox(height: 12),
                const Text('Send emergency alert to kindergarten administration?', style: TextStyle(fontFamily: 'Lexend')),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                    child: const Text('SEND ALERT', style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w700)),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel', style: TextStyle(fontFamily: 'Lexend')),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final pos = await LocationService.getCurrentPositionBestEffort();
      final lat = pos?.latitude ?? 3.1390;
      final lng = pos?.longitude ?? 101.6869;

      await _sendAlertWithRetry(
        driverId: _currentUserId,
        busId: _activeSession!.busId,
        sessionId: _activeSession!.id,
        latitude: lat,
        longitude: lng,
      );

      await _waitForNextFrame();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      if (mounted && pos == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location unavailable — alert used a fallback area. Enable location for precise coordinates.',
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: Color(0xFFFF9800),
          ),
        );
      }

      if (mounted) {
        showAppModalSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Alert Sent', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 24)),
                    const SizedBox(height: 12),
                    const Text('Emergency alert has been sent to kindergarten administration.', style: TextStyle(fontFamily: 'Lexend')),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK', style: TextStyle(fontFamily: 'Lexend')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = _emergencyAlertErrorMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              msg,
              style: const TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Retries the Firestore emergency alert up to [maxAttempts] times when the
  /// web SDK throws its internal WatchChangeAggregator / ASSERTION errors.
  static Future<String> _sendAlertWithRetry({
    required String driverId,
    required String busId,
    required String sessionId,
    required double latitude,
    required double longitude,
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await FirebaseService.createEmergencyAlert(
          driverId: driverId,
          busId: busId,
          sessionId: sessionId,
          latitude: latitude,
          longitude: longitude,
        );
      } catch (e) {
        lastError = e;
        if (attempt < maxAttempts && _isFirestoreWebSyncError(e)) {
          await Future<void>.delayed(
            Duration(milliseconds: 400 * attempt),
          );
          continue;
        }
        rethrow;
      }
    }
    throw lastError!;
  }

  static bool _isFirestoreWebSyncError(Object e) {
    final s = e.toString();
    return s.contains('INTERNAL ASSERTION') ||
        s.contains('Unexpected state') ||
        s.contains('WatchChangeAggregator');
  }

  static String _emergencyAlertErrorMessage(Object e) {
    if (_isFirestoreWebSyncError(e)) {
      return 'Could not send alert after retries (browser sync). Please try again.';
    }
    final s = e.toString();
    if (s.length > 200) {
      return 'Error sending alert: ${s.substring(0, 200)}…';
    }
    return 'Error sending alert: $e';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFCAF0F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFCAF0F8),
        elevation: 0,
        foregroundColor: const Color(0xFF03045E),
        title: const Text(
          'Driver Dashboard',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: Color(0xFF03045E),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.emergency, color: Colors.red),
            onPressed: _onEmergencyPressed,
            tooltip: 'Emergency Alert',
            iconSize: 28,
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          DriverNFCTab(
            activeSession: _activeSession,
            nfcTabActive: _currentTabIndex == 0,
          ),
          DriverMapTab(
            activeSession: _activeSession,
            mapTabActive: _currentTabIndex == 1,
          ),
          DriverTripTab(
            activeSession: _activeSession,
            onToggleSession: _toggleRouteSession,
            isLoading: _isLoading,
            assignedBuses: _assignedBuses,
            selectedBusId: _selectedBusId,
            onSelectBus: _onSelectBus,
          ),
          DriverStudentsTab(activeSession: _activeSession),
          const SharedProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFFCAF0F8),
        indicatorColor: const Color(0xFF00B4D8).withValues(alpha: 0.3),
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentTabIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.nfc_outlined),
            selectedIcon: Icon(Icons.nfc, color: Color(0xFF0077B6)),
            label: 'NFC',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map, color: Color(0xFF0077B6)),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route, color: Color(0xFF0077B6)),
            label: 'Trip',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups, color: Color(0xFF0077B6)),
            label: 'Students',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: Color(0xFF0077B6)),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

}

