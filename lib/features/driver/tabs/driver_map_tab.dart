import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/config.dart';
import 'package:schoolway/core/fleet_bus_position.dart';
import 'package:schoolway/core/widgets/osm_map_attribution.dart';
import 'package:schoolway/core/widgets/osm_map_tile_layer.dart';
import 'package:schoolway/core/widgets/debug_bus_joystick.dart';
import 'package:schoolway/core/widgets/fleet_bus_marker.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/driver_gps_uploader.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/services/location_service.dart';
import 'package:schoolway/services/stationary_bus_detector.dart';
import 'package:schoolway/services/eta_geofence_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DriverMapTab extends StatefulWidget {
  final RouteSession? activeSession;

  /// When false (another bottom tab selected), the map is offstage — web often
  /// needs a nudge when this becomes true so tiles load ([IndexedStack]).
  final bool mapTabActive;

  const DriverMapTab({
    super.key,
    required this.activeSession,
    this.mapTabActive = true,
  });

  @override
  State<DriverMapTab> createState() => _DriverMapTabState();
}

class _DriverMapTabState extends State<DriverMapTab> {
  static const LatLng _fallbackCenter = LatLng(3.1390, 101.6869);

  final MapController _mapController = MapController();
  final DriverGpsUploader _uploader = DriverGpsUploader();

  StreamSubscription<GpsTracking?>? _gpsSub;
  StreamSubscription<Bus?>? _busSub;
  StreamSubscription<List<Student>>? _studentsSub;
  GpsTracking? _gps;
  Bus? _bus;
  LatLng? _myLocation;
  bool _centeredOnFirstFix = false;

  /// Debug builds only: fake GPS via joystick (does not use device location).
  bool _debugJoystickEnabled = false;
  Timer? _debugTick;
  Offset _debugDir = Offset.zero;
  double _simLat = 0;
  double _simLng = 0;
  double _prevLat = 0;
  double _prevLng = 0;
  // Firestore has a 1-write/second limit per document; throttle broadcasts so
  // admin/parent views stay in sync without hitting rate limits.
  DateTime? _debugLastFirestoreWrite;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initSessionAndMaybeRefreshTiles());
    });
  }

  Future<void> _initSessionAndMaybeRefreshTiles() async {
    await _syncSession(widget.activeSession);
    if (!mounted || !widget.mapTabActive) return;
    _scheduleMapTileRefresh();
  }

  @override
  void didUpdateWidget(DriverMapTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeSession?.id != widget.activeSession?.id) {
      unawaited(
        _syncSession(widget.activeSession).then((_) {
          if (mounted && widget.mapTabActive) _scheduleMapTileRefresh();
        }),
      );
    } else if (!oldWidget.mapTabActive && widget.mapTabActive) {
      _scheduleMapTileRefresh();
    }
  }

  /// flutter_map on web often shows a grey canvas until the camera moves after
  /// the widget becomes visible (e.g. switching to this tab in [IndexedStack]).
  void _scheduleMapTileRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshMapTiles();
    });
  }

  void _refreshMapTiles() {
    if (!mounted) return;
    try {
      final c = _mapController.camera;
      _mapController.move(c.center, c.zoom);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'data',
        'Malformed or unavailable optional data was ignored.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _maybeCenterOnFirstFix() {
    if (!_followBus) return;
    final p = fleetBusMapPosition(gps: _gps, bus: _bus);
    if (p == null || _centeredOnFirstFix) return;
    _centeredOnFirstFix = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.move(p, 15);
      } catch (error, stackTrace) {
        AppLogger.warning(
          'data',
          'Malformed or unavailable optional data was ignored.',
          error: error,
          stackTrace: stackTrace,
        );
      }
      _scheduleMapTileRefresh();
    });
  }

  PlannedRoute? _plannedRoute;
  List<AssignedRouteStop> _assignedStops = const [];
  bool _followBus = true;

  Future<void> _syncSession(RouteSession? session) async {
    _gpsSub?.cancel();
    _gpsSub = null;
    _busSub?.cancel();
    _busSub = null;
    _studentsSub?.cancel();
    _studentsSub = null;
    _stopDebugTick();
    if (!mounted) return;
    setState(() {
      _gps = null;
      _bus = null;
      _centeredOnFirstFix = false;
      _debugJoystickEnabled = false;
      _plannedRoute = null;
      _assignedStops = const [];
    });

    StationaryBusDetector().stop();
    await _uploader.stop();
    if (!mounted) return;

    if (session == null) {
      EtaGeofenceService.clearSession('');
      return;
    }

    if (session.routeId != null) {
      _plannedRoute = await FirebaseService.getPlannedRouteById(
        session.routeId!,
      );
    }

    _studentsSub = FirebaseService.getStudentsByBusId(session.busId).listen(
      (students) {
        final route = _plannedRoute;
        if (!mounted || route == null) return;
        setState(() {
          _assignedStops = buildAssignedRouteStops(
            route: route,
            busId: session.busId,
            direction: session.tripDirection,
            students: students,
          );
        });
      },
      onError: (Object error, StackTrace stackTrace) => AppLogger.error(
        'students',
        'Assigned student monitoring failed.',
        error: error,
        stackTrace: stackTrace,
      ),
    );

    await _uploader.start(busId: session.busId, sessionId: session.id);
    StationaryBusDetector().start(
      busId: session.busId,
      sessionId: session.id,
      onWarning: _showStationaryWarning,
    );
    if (!mounted) return;

    _gpsSub = FirebaseService.getGpsTrackingForBus(session.busId).listen(
      (gps) async {
        if (!mounted) return;
        setState(() => _gps = gps);
        if (_followBus) {
          final p = fleetBusMapPosition(gps: _gps, bus: _bus);
          if (p != null) {
            _mapController.move(p, _mapController.camera.zoom);
          }
        }
        _maybeCenterOnFirstFix();
        if (gps != null) {
          StationaryBusDetector().updateGps(gps);
          if (_assignedStops.isNotEmpty) {
            final event = await EtaGeofenceService.processLocationUpdate(
              sessionId: session.id,
              busId: session.busId,
              driverUid: session.driverUid,
              currentPos: LatLng(gps.latitude, gps.longitude),
              stops: _assignedStops,
            );
            if (event != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${event.type == GeofenceEventType.atStop ? "Arrived at" : "Departed"} stop ${event.stopIndex + 1}',
                    style: TextStyle(fontFamily: 'Lexend'),
                  ),
                  backgroundColor: SchoolWayTheme.accent,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) => AppLogger.error(
        'location',
        'Bus location monitoring failed.',
        error: error,
        stackTrace: stackTrace,
      ),
    );

    _busSub = FirebaseService.watchBusById(session.busId).listen(
      (bus) {
        if (!mounted) return;
        setState(() => _bus = bus);
        _maybeCenterOnFirstFix();
      },
      onError: (Object error, StackTrace stackTrace) => AppLogger.error(
        'buses',
        'Bus status monitoring failed.',
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  void _stopDebugTick() {
    _debugTick?.cancel();
    _debugTick = null;
  }

  void _onDebugDirection(Offset dir) {
    _debugDir = dir;
  }

  void _startDebugMovementLoop() {
    _stopDebugTick();
    final session = widget.activeSession;
    if (session == null || !_debugJoystickEnabled) return;

    _debugTick = Timer.periodic(Duration(milliseconds: 100), (_) {
      if (!mounted || !_debugJoystickEnabled) return;
      final s = widget.activeSession;
      if (s == null) return;
      final d = _debugDir;
      final now = DateTime.now();
      // Broadcast to Firestore at most every 500 ms — keeps admin/parent in sync
      // while staying well within Firestore's per-document write rate limit.
      final canWriteFirestore =
          _debugLastFirestoreWrite == null ||
          now.difference(_debugLastFirestoreWrite!).inMilliseconds >= 500;

      if (d.distance < 0.008) {
        // Joystick at rest — emit a stopped update so speed reads 0 km/h.
        if (_gps != null) {
          final stopped = GpsTracking(
            busId: s.busId,
            latitude: _simLat,
            longitude: _simLng,
            speed: 0,
            heading: _gps!.heading,
            accuracy: 4,
            timestamp: now,
            sessionId: s.id,
            driverUid: FirebaseAuth.instance.currentUser?.uid,
            isSimulated: true,
          );
          StationaryBusDetector().updateGps(stopped);
          if (_gps!.speed > 0 || canWriteFirestore) {
            setState(() => _gps = stopped);
          }
          if (canWriteFirestore) {
            _debugLastFirestoreWrite = now;
            unawaited(FirebaseService.updateGpsLocation(stopped));
          }
        }
        return;
      }

      const kStep = 0.000055;
      // Joystick vector is in ~[-1,1] per axis; distance is up to √2 at corners.
      // Do not clamp to 1 — that capped movement and reported speed at ~42 km/h.
      final mag = d.distance;
      final lat = _simLat - d.dy * kStep * mag;
      final lng = _simLng + d.dx * kStep * mag;

      final dlat = lat - _prevLat;
      final dlng = lng - _prevLng;
      var heading = 0.0;
      if (dlat * dlat + dlng * dlng > 1e-16) {
        heading = math.atan2(dlng, dlat) * 180 / math.pi;
        if (heading < 0) heading += 360;
      }

      _prevLat = lat;
      _prevLng = lng;
      _simLat = lat;
      _simLng = lng;

      final speed = 200.0 * mag / math.sqrt2;
      final fakeGps = GpsTracking(
        busId: s.busId,
        latitude: lat,
        longitude: lng,
        speed: speed,
        heading: heading,
        accuracy: 4,
        timestamp: now,
        sessionId: s.id,
        driverUid: FirebaseAuth.instance.currentUser?.uid,
        isSimulated: true,
      );

      // Update local state immediately so the driver map pin moves without
      // waiting for the Firestore round-trip.
      setState(() => _gps = fakeGps);
      StationaryBusDetector().updateGps(fakeGps);

      // Broadcast to Firestore at most once per second so admin / parent views
      // stay in sync without hitting Firestore's per-document write rate limit.
      if (canWriteFirestore) {
        _debugLastFirestoreWrite = now;
        unawaited(FirebaseService.updateGpsLocation(fakeGps));
      }
    });
  }

  Future<void> _setDebugJoystick(bool enabled) async {
    final session = widget.activeSession;
    if (session == null) return;

    if (enabled) {
      await _uploader.stop();
      if (!mounted) return;

      // Pause the Firestore GPS subscription while debug mode is active; the tick
      // loop drives _gps directly so the map responds instantly without a round-trip.
      _gpsSub?.cancel();
      _gpsSub = null;

      // Seed priority: live Firestore GPS → bus.lastLocation → device GPS → fallback.
      LatLng? seed = fleetBusMapPosition(gps: _gps, bus: _bus);
      if (seed == null) {
        final devicePos = await LocationService.getCurrentPositionBestEffort();
        if (devicePos != null) {
          seed = LatLng(devicePos.latitude, devicePos.longitude);
        }
      }
      if (!mounted) return;

      _simLat = seed?.latitude ?? _fallbackCenter.latitude;
      _simLng = seed?.longitude ?? _fallbackCenter.longitude;
      _prevLat = _simLat;
      _prevLng = _simLng;
      _debugDir = Offset.zero;
      _debugLastFirestoreWrite = null;
      setState(() => _debugJoystickEnabled = true);
      _startDebugMovementLoop();
    } else {
      _stopDebugTick();
      _debugDir = Offset.zero;
      if (!mounted) return;
      setState(() => _debugJoystickEnabled = false);

      // Restore Firestore GPS subscription now that debug mode is off.
      _gpsSub?.cancel();
      _gpsSub = FirebaseService.getGpsTrackingForBus(session.busId).listen(
        (gps) {
          if (!mounted) return;
          setState(() => _gps = gps);
          _maybeCenterOnFirstFix();
        },
        onError: (Object error, StackTrace stackTrace) => AppLogger.error(
          'location',
          'Bus location monitoring failed.',
          error: error,
          stackTrace: stackTrace,
        ),
      );

      await _uploader.start(busId: session.busId, sessionId: session.id);
    }
  }

  Future<void> _toggleSimulation() async {
    if (widget.activeSession == null) return;
    await _setDebugJoystick(!_debugJoystickEnabled);
  }

  void _showStationaryWarning() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: Duration(seconds: 12),
        backgroundColor: SchoolWayTheme.warning,
        content: Text(
          AppLocalizations.of(context).busStationaryFor7MinutesAnEmergency,
          style: TextStyle(fontFamily: 'Lexend'),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stopDebugTick();
    _gpsSub?.cancel();
    _busSub?.cancel();
    _studentsSub?.cancel();
    unawaited(_uploader.stop());
    final controller = _mapController;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
    super.dispose();
  }

  /// Re-center: with Debug drive on, uses **device GPS** so you can see your real
  /// position vs the simulated bus. Otherwise centers on live bus position from Firestore.
  Future<void> _handleRecenter() async {
    if (_debugJoystickEnabled) {
      final pos = await LocationService.getCurrentPositionBestEffort();
      if (!mounted) return;
      if (pos == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).couldNotGetYourGpsLocationCheck2,
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: SchoolWayTheme.warning,
          ),
        );
        return;
      }
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      try {
        _mapController.move(LatLng(pos.latitude, pos.longitude), 15);
      } catch (error, stackTrace) {
        AppLogger.warning(
          'data',
          'Malformed or unavailable optional data was ignored.',
          error: error,
          stackTrace: stackTrace,
        );
      }
      return;
    }
    final pin = fleetBusMapPosition(gps: _gps, bus: _bus);
    if (pin == null) return;
    setState(() => _followBus = true);
    try {
      _mapController.move(pin, 15);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'data',
        'Malformed or unavailable optional data was ignored.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _zoomIn() {
    try {
      final c = _mapController.camera;
      _mapController.move(c.center, (c.zoom + 1).clamp(3, 19));
    } catch (error, stackTrace) {
      AppLogger.warning(
        'data',
        'Malformed or unavailable optional data was ignored.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _zoomOut() {
    try {
      final c = _mapController.camera;
      _mapController.move(c.center, (c.zoom - 1).clamp(3, 19));
    } catch (error, stackTrace) {
      AppLogger.warning(
        'data',
        'Malformed or unavailable optional data was ignored.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activeSession == null) {
      return _buildInactiveView();
    }

    final pin = fleetBusMapPosition(gps: _gps, bus: _bus);
    final center = pin ?? _fallbackCenter;
    final routeId = widget.activeSession?.routeId;

    return StreamBuilder<List<Student>>(
      stream: FirebaseService.getStudentsByBusId(widget.activeSession!.busId),
      builder: (context, studentSnap) {
        final assignedStudents = studentSnap.data ?? const <Student>[];

        return StreamBuilder<List<PlannedRoute>>(
          stream: FirebaseService.getPlannedRoutes(),
          builder: (context, plannedSnap) {
            PlannedRoute? planned;
            if (routeId != null && routeId.trim().isNotEmpty) {
              for (final r in plannedSnap.data ?? const <PlannedRoute>[]) {
                if (r.id == routeId) {
                  planned = r;
                  break;
                }
              }
            }
            final tripDir = widget.activeSession!.tripDirection;
            final routePolylinePoints = (planned == null)
                ? const <LatLng>[]
                : planned
                      .waypointsForTrip(tripDir)
                      .map((w) => LatLng(w.latitude, w.longitude))
                      .toList();
            final stopMarkers = <Marker>[];
            final orderedStops = planned == null
                ? const <AssignedRouteStop>[]
                : buildAssignedRouteStops(
                    route: planned,
                    busId: widget.activeSession!.busId,
                    direction: tripDir,
                    students: assignedStudents,
                  );

            for (var i = 0; i < orderedStops.length; i++) {
              final assignedStop = orderedStops[i];
              final stop = assignedStop.waypoint;
              final stopPos = LatLng(stop.latitude, stop.longitude);
              final count = assignedStop.students.length;

              stopMarkers.add(
                Marker(
                  point: stopPos,
                  width: 80,
                  height: 60,
                  alignment: Alignment.topCenter,
                  child: Column(
                    children: [
                      if (count > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: SchoolWayTheme.surface.withValues(
                              alpha: 0.9,
                            ),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: SchoolWayTheme.accent,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '$count student${count > 1 ? 's' : ''}',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: SchoolWayTheme.navy,
                            ),
                          ),
                        ),
                      SizedBox(height: 2),
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: SchoolWayTheme.accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: SchoolWayTheme.surface,
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${assignedStop.routeStopIndex + 1}',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            color: SchoolWayTheme.surface,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return SafeArea(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: 14,
                        onPositionChanged: (pos, hasGesture) {
                          if (hasGesture && _followBus) {
                            setState(() => _followBus = false);
                          }
                        },
                      ),
                      children: [
                        OsmMapTileLayer(),
                        if (routePolylinePoints.length >= 2)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: routePolylinePoints,
                                strokeWidth: 4,
                                color: Color(
                                  0xFF0077B6,
                                ).withValues(alpha: 0.75),
                              ),
                            ],
                          ),
                        if (pin != null ||
                            _myLocation != null ||
                            stopMarkers.isNotEmpty)
                          MarkerLayer(
                            markers: [
                              ...stopMarkers,
                              if (_myLocation != null)
                                Marker(
                                  point: _myLocation!,
                                  width: 18,
                                  height: 18,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: SchoolWayTheme.info,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: SchoolWayTheme.surface,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              if (pin != null)
                                buildFleetBusMarker(
                                  point: pin,
                                  busId: widget.activeSession!.busId,
                                  busLabel: _bus?.busNumber ?? 'BUS',
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: OsmMapAttribution(compact: true),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: SchoolWayTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: SchoolWayTheme.text.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                color: SchoolWayTheme.primary,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                AppLocalizations.of(context).livePosition,
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: SchoolWayTheme.navy,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          _buildLocationRow(
                            Icons.speed,
                            'Speed',
                            _gps != null
                                ? '${_gps!.speed.toStringAsFixed(0)} km/h'
                                : '—',
                          ),
                          SizedBox(height: 8),
                          _buildLocationRow(
                            Icons.gps_fixed,
                            'GPS',
                            _gps != null
                                ? 'Live fix'
                                : (pin != null
                                      ? 'Saved on bus'
                                      : 'Waiting for fix…'),
                          ),
                          SizedBox(height: 8),
                          _buildLocationRow(
                            Icons.update,
                            'Last updated',
                            fleetBusLastSeenLabel(gps: _gps, bus: _bus),
                          ),
                          if (_gps?.isSimulated == true) ...[
                            SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Chip(
                                avatar: Icon(Icons.science_outlined, size: 16),
                                label: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).simulatedPosition,
                                  style: TextStyle(fontFamily: 'Lexend'),
                                ),
                              ),
                            ),
                          ],
                          SizedBox(height: 8),
                          Text(
                            _debugJoystickEnabled
                                ? 'Debug joystick: fake position (no device GPS)'
                                : 'Uploads every ${AppConfig.gpsUploadInterval.inSeconds}s',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12,
                              color: SchoolWayTheme.blueGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 40,
                    right: 16,
                    child: Column(
                      children: [
                        _buildMapControlButton(
                          Icons.my_location,
                          _debugJoystickEnabled
                              ? 'Locate me (device GPS)'
                              : 'Re-center on bus',
                          (pin != null || _debugJoystickEnabled)
                              ? () => unawaited(_handleRecenter())
                              : null,
                        ),
                        SizedBox(height: 8),
                        _buildMapControlButton(Icons.add, 'Zoom in', _zoomIn),
                        SizedBox(height: 8),
                        _buildMapControlButton(
                          Icons.remove,
                          AppLocalizations.of(context).zoomOut,
                          _zoomOut,
                        ),
                        if (widget.activeSession != null) ...[
                          SizedBox(height: 8),
                          _buildMapControlButton(
                            Icons.science_outlined,
                            AppLocalizations.of(context).busSimulation,
                            () => unawaited(_toggleSimulation()),
                            isActive: _debugJoystickEnabled,
                            activeColor: SchoolWayTheme.warning,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_debugJoystickEnabled)
                    Positioned(
                      key: const ValueKey('debug-map-joystick'),
                      top: 72,
                      left: 16,
                      child: DebugBusJoystick(
                        size: 120,
                        semanticLabel: AppLocalizations.of(
                          context,
                        ).dragTheControllerToMoveTheBus,
                        onDirectionChanged: _onDebugDirection,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLocationRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: SchoolWayTheme.primary),
        SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14,
            color: SchoolWayTheme.primary,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: SchoolWayTheme.navy,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapControlButton(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool isActive = false,
    Color? activeColor,
  }) {
    final selectedColor = activeColor ?? SchoolWayTheme.primary;
    return Material(
      color: isActive ? selectedColor : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: SizedBox.square(
        dimension: 48,
        child: IconButton(
          icon: Icon(
            icon,
            color: isActive
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.primary,
          ),
          onPressed: onPressed,
          tooltip: tooltip,
        ),
      ),
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
                color: SchoolWayTheme.muted.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.map_outlined,
                size: 100,
                color: SchoolWayTheme.muted,
              ),
            ),
            SizedBox(height: 24),
            Text(
              AppLocalizations.of(context).gpsTrackingDisabled,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: SchoolWayTheme.muted,
              ),
            ),
            SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).startARouteSessionToShareLive,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 16,
                color: SchoolWayTheme.primary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
