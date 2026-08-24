import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
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
import 'package:schoolway/core/widgets/responsive_role_shell.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  static const routeName = '/driver';

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  RouteSession? _activeSession;
  List<Bus> _assignedBuses = [];
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
        .where('currentDriverUid', isEqualTo: _currentUserId)
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
              _selectedBusId = _assignedBuses.isNotEmpty
                  ? _assignedBuses.first.id
                  : null;
            }
          });
        });
  }

  Future<void> _loadAssignedBuses() async {
    if (_currentUserId == null) return;

    final assignedBusSnapshot = await FirebaseService.busesCollection
        .where('currentDriverUid', isEqualTo: _currentUserId)
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
        _selectedBusId = _assignedBuses.isNotEmpty
            ? _assignedBuses.first.id
            : null;
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
      throw Exception(
        'No bus assigned to you. Solution: Please ask your school administrator to assign a bus to you in their dashboard.',
      );
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
      backgroundColor: SchoolWayTheme.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: SchoolWayTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppLocalizations.of(context).tripDirection,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: SchoolWayTheme.navy,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context).mapPinsAndRouteOrderFollowYour,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14,
                    color: SchoolWayTheme.muted,
                    height: 1.35,
                  ),
                ),
                SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, TripDirection.toSchool),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SchoolWayTheme.navy,
                      foregroundColor: SchoolWayTheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      AppLocalizations.of(context).toSchool,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(ctx, TripDirection.fromSchool),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SchoolWayTheme.navy,
                      side: BorderSide(color: SchoolWayTheme.navy),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      AppLocalizations.of(context).fromSchool,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
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

  Future<void> _startOrResumeSession(Bus bus) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return;

    if (bus.assignedRouteId == null || bus.assignedRouteId!.isEmpty) {
      throw Exception(
        'This bus does not have a route assigned. Solution: Please ask your school administrator to assign a route to this bus.',
      );
    }

    if (bus.status.toLowerCase() == 'active') {
      final existingSession = await FirebaseService.getActiveSessionForBus(
        bus.id,
      );
      if (existingSession != null &&
          existingSession.driverUid == currentUserId) {
        setState(() {
          _activeSession = existingSession;
          _selectedBusId = bus.id;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).resumedYourActiveRouteSession,
                style: TextStyle(fontFamily: 'Lexend'),
              ),
              backgroundColor: SchoolWayTheme.info,
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
          driverUid: currentUserId,
          busId: bus.id,
          routeId: bus.assignedRouteId,
          tripDirection: tripDirection,
        );
        final sessionDoc = await FirebaseService.routeSessionsCollection
            .doc(sessionId)
            .get();
        setState(() {
          _activeSession = RouteSession.fromFirestore(sessionDoc);
          _selectedBusId = bus.id;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(
                  context,
                ).routeSessionStartedFromActiveBusAssignment,
                style: TextStyle(fontFamily: 'Lexend'),
              ),
              backgroundColor: SchoolWayTheme.success,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      throw Exception(
        'Assigned bus is currently "Active" under another driver. Solution: Ensure the other driver ends their session, or ask an admin to reset the bus status.',
      );
    }

    if (bus.status.toLowerCase() != 'idle') {
      throw Exception(
        'Assigned bus is currently "${bus.status}". Solution: Ask your school administrator to reset the bus status to Idle.',
      );
    }

    final tripDirection = await _pickTripDirection();
    if (!mounted || tripDirection == null) return;

    final sessionId = await FirebaseService.startRouteSession(
      driverUid: currentUserId,
      busId: bus.id,
      routeId: bus.assignedRouteId,
      tripDirection: tripDirection,
    );
    final sessionDoc = await FirebaseService.routeSessionsCollection
        .doc(sessionId)
        .get();

    setState(() {
      _activeSession = RouteSession.fromFirestore(sessionDoc);
      _selectedBusId = bus.id;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).routeSessionStartedReadyToScanNfc,
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: SchoolWayTheme.success,
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
                        Icon(
                          Icons.warning_amber_rounded,
                          color: SchoolWayTheme.warning,
                          size: 48,
                        ),
                        SizedBox(height: 12),
                        Text(
                          AppLocalizations.of(context).cannotEndTrip,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          '$onBoardCount student${onBoardCount == 1 ? ' is' : 's are'} still on board.\n'
                          'Solution: Please switch to the Students tab and mark all boarded students as Dropped Off before ending the route session.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14,
                            color: SchoolWayTheme.navy,
                            height: 1.5,
                          ),
                        ),
                        SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SchoolWayTheme.primary,
                            foregroundColor: SchoolWayTheme.surface,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            AppLocalizations.of(context).ok,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
          final recovered = await FirebaseService.getActiveSessionForDriver(
            uid,
          );
          if (mounted && recovered != null && recovered.id == sessionId) {
            setState(() => _activeSession = recovered);
          }
          rethrow;
        }
        await _loadAssignedBuses();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).routeSessionEndedDataSynced,
                style: TextStyle(fontFamily: 'Lexend'),
              ),
              backgroundColor: SchoolWayTheme.warning,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e', style: TextStyle(fontFamily: 'Lexend')),
            backgroundColor: SchoolWayTheme.danger,
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
        SnackBar(
          content: Text(
            AppLocalizations.of(context).cannotSendAlertSolutionPleaseStartA,
            style: TextStyle(fontFamily: 'Lexend'),
          ),
        ),
      );
      return;
    }

    // Show confirmation dialog first
    final confirmed = await showAppModalSheet<bool>(
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
                  AppLocalizations.of(context).emergencyAlert,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  AppLocalizations.of(
                    context,
                  ).sendEmergencyAlertToKindergartenAdministration,
                  style: TextStyle(fontFamily: 'Lexend'),
                ),
                SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SchoolWayTheme.danger,
                      foregroundColor: SchoolWayTheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      AppLocalizations.of(context).sendAlert,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
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

    if (confirmed != true) return;

    try {
      final pos = await LocationService.getCurrentPositionBestEffort();
      final lat = pos?.latitude ?? 3.1390;
      final lng = pos?.longitude ?? 101.6869;

      await _sendAlertWithRetry(
        driverUid: _currentUserId,
        busId: _activeSession!.busId,
        sessionId: _activeSession!.id,
        latitude: lat,
        longitude: lng,
      );

      await _waitForNextFrame();
      await Future<void>.delayed(Duration(milliseconds: 50));

      if (mounted && pos == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              ).locationUnavailableAlertUsedAFallbackArea,
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: SchoolWayTheme.warning,
          ),
        );
      }

      if (mounted) {
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
                      AppLocalizations.of(context).alertSent,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      AppLocalizations.of(
                        context,
                      ).emergencyAlertHasBeenSentToKindergarten,
                      style: TextStyle(fontFamily: 'Lexend'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        AppLocalizations.of(context).ok,
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
    } catch (e) {
      if (mounted) {
        final msg = _emergencyAlertErrorMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, style: TextStyle(fontFamily: 'Lexend')),
            backgroundColor: SchoolWayTheme.danger,
          ),
        );
      }
    }
  }

  /// Retries the Firestore emergency alert up to [maxAttempts] times when the
  /// web SDK throws its internal WatchChangeAggregator / ASSERTION errors.
  static Future<String> _sendAlertWithRetry({
    required String driverUid,
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
          driverUid: driverUid,
          busId: busId,
          sessionId: sessionId,
          latitude: latitude,
          longitude: longitude,
        );
      } catch (e) {
        lastError = e;
        if (attempt < maxAttempts && _isFirestoreWebSyncError(e)) {
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
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
    return ResponsiveRoleShell(
      title: 'Driver Dashboard',
      selectedIndex: _currentTabIndex,
      onDestinationSelected: (index) =>
          setState(() => _currentTabIndex = index),
      actions: [
        IconButton(
          icon: Icon(Icons.emergency, color: SchoolWayTheme.danger),
          onPressed: _onEmergencyPressed,
          tooltip: AppLocalizations.of(context).emergencyAlert,
          iconSize: 28,
        ),
      ],
      destinations: [
        RoleDestination(
          label: AppLocalizations.of(context).nfc,
          icon: Icons.nfc_outlined,
          selectedIcon: Icons.nfc,
        ),
        RoleDestination(
          label: AppLocalizations.of(context).map,
          icon: Icons.map_outlined,
          selectedIcon: Icons.map,
        ),
        RoleDestination(
          label: AppLocalizations.of(context).trip,
          icon: Icons.route_outlined,
          selectedIcon: Icons.route,
        ),
        RoleDestination(
          label: AppLocalizations.of(context).students,
          icon: Icons.groups_outlined,
          selectedIcon: Icons.groups,
        ),
      ],
      children: [
        DriverNFCTab(
          activeSession: _activeSession,
          nfcTabActive: _currentTabIndex == 0,
          onManualFallback: () {
            setState(() {
              _currentTabIndex = 3;
            });
          },
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
        SharedProfileTab(),
      ],
    );
  }
}
