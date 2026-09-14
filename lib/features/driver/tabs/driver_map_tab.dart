import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/config.dart';
import 'package:schoolway/core/fleet_bus_position.dart';
import 'package:schoolway/core/map/map_markers.dart';
import 'package:schoolway/core/map/schoolway_map.dart';
import 'package:schoolway/core/map/schoolway_map_controller.dart';
import 'package:schoolway/core/widgets/debug_bus_joystick.dart';
import 'package:schoolway/core/widgets/route_geometry_missing_banner.dart';
import 'package:schoolway/core/widgets/simulated_location_badge.dart';
import 'package:schoolway/core/widgets/traffic_eta_chip.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/driver_gps_uploader.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/services/location_service.dart';
import 'package:schoolway/services/stationary_bus_detector.dart';
import 'package:schoolway/services/eta_geofence_service.dart';
import 'package:schoolway/services/traffic_eta_service.dart';
import 'package:schoolway/services/school_config_service.dart';
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

  final SchoolWayMapController _mapController = SchoolWayMapController();
  final DriverGpsUploader _uploader = DriverGpsUploader();

  StreamSubscription<GpsTracking?>? _gpsSub;
  StreamSubscription<Bus?>? _busSub;
  StreamSubscription<List<Student>>? _studentsSub;
  GpsTracking? _gps;
  Bus? _bus;
  LatLng? _myLocation;
  bool _centeredOnFirstFix = false;
  double _zoom = 14;
  final TrafficEtaService _trafficEta = TrafficEtaService();

  /// Driver-controlled fake GPS via joystick (does not use device location).
  bool _debugJoystickEnabled = false;
  Timer? _debugTick;
  Offset _debugDir = Offset.zero;
  double _simLat = 0;
  double _simLng = 0;
  double _prevLat = 0;
  double _prevLng = 0;
  // Firestore has a 1-write/second limit per document; throttle broadcasts so
  // admin/parent views stay in sync without hitting rate limits.

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

  /// Google Maps on web handles its own tiles.
  void _scheduleMapTileRefresh() {
    // No-op.
  }

  void _maybeCenterOnFirstFix() {
    if (!_followBus) return;
    final p = fleetBusMapPosition(gps: _gps, bus: _bus);
    if (p == null || _centeredOnFirstFix) return;
    _centeredOnFirstFix = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(center: p, zoom: 15);
    });
  }

  PlannedRoute? _plannedRoute;
  List<AssignedRouteStop> _assignedStops = const [];
  bool _followBus = true;
  SchoolGeofenceConfig _geofenceConfig = const SchoolGeofenceConfig.disabled();

  Future<void> _syncSession(RouteSession? session) async {
    _gpsSub?.cancel();
    _gpsSub = null;
    _busSub?.cancel();
    _busSub = null;
    _studentsSub?.cancel();
    _studentsSub = null;
    _stopDebugTick();
    _trafficEta.stop();
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

    _trafficEta.start(session.id);

    if (session.routeId != null) {
      _plannedRoute = await FirebaseService.getPlannedRouteById(
        session.routeId!,
      );
    }
    try {
      _geofenceConfig = await SchoolConfigService.getGeofenceConfig();
    } catch (error, stackTrace) {
      AppLogger.warning(
        'location',
        'School geofence configuration could not be loaded.',
        error: error,
        stackTrace: stackTrace,
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
            serviceStopRouteIndices: session.serviceStopRouteIndices,
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
            _mapController.move(center: p, zoom: _zoom);
          }
        }
        _maybeCenterOnFirstFix();
        if (gps != null) {
          StationaryBusDetector().updateGps(gps);
          final routeWaypoints = _plannedRoute?.waypointsForTrip(
            session.tripDirection,
          );
          if (_geofenceConfig.enabled &&
              routeWaypoints != null &&
              routeWaypoints.length >= 2) {
            final deviated =
                await EtaGeofenceService.processRouteCorridorUpdate(
                  sessionId: session.id,
                  busId: session.busId,
                  driverUid: session.driverUid,
                  currentPos: LatLng(gps.latitude, gps.longitude),
                  routeWaypoints: routeWaypoints,
                  corridorMeters: _geofenceConfig.routeCorridorMeters,
                );
            if (deviated && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context).busLeftRouteGeofence,
                  ),
                  backgroundColor: SchoolWayTheme.danger,
                ),
              );
            }
          }
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
                    '${event.type == GeofenceEventType.atStop ? "Arrived at" : "Departed"} ${event.stopLabel}',
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

  DateTime? _lastSimUploadAt;
  bool _simUploadInProgress = false;

  void _maybeUploadSimulatedGps(GpsTracking tracking, {bool force = false}) {
    final now = DateTime.now();
    if (_simUploadInProgress) return;
    if (!force &&
        _lastSimUploadAt != null &&
        now.difference(_lastSimUploadAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastSimUploadAt = now;
    _simUploadInProgress = true;
    FirebaseService.updateGpsLocation(tracking)
        .then((_) {
          _simUploadInProgress = false;
        })
        .catchError((Object error, StackTrace stackTrace) {
          _simUploadInProgress = false;
          AppLogger.warning(
            'location',
            'Simulated GPS upload failed.',
            error: error,
            stackTrace: stackTrace,
          );
        });
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
          LocationService.rememberCoordinates(
            latitude: _simLat,
            longitude: _simLng,
            speed: 0,
            heading: _gps!.heading,
            accuracy: 4,
            timestamp: now,
          );
          if (_gps!.speed > 0) {
            setState(() => _gps = stopped);
            _maybeUploadSimulatedGps(stopped, force: true);
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
      LocationService.rememberCoordinates(
        latitude: lat,
        longitude: lng,
        speed: speed,
        heading: heading,
        accuracy: 4,
        timestamp: now,
      );
      _maybeUploadSimulatedGps(fakeGps);
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
      LocationService.setSimulated(true);
      LocationService.rememberCoordinates(
        latitude: _simLat,
        longitude: _simLng,
        accuracy: 4,
      );
      final initialSimGps = GpsTracking(
        busId: session.busId,
        latitude: _simLat,
        longitude: _simLng,
        speed: 0,
        heading: _gps?.heading ?? 0,
        accuracy: 4,
        timestamp: DateTime.now(),
        sessionId: session.id,
        driverUid: FirebaseAuth.instance.currentUser?.uid,
        isSimulated: true,
      );
      _maybeUploadSimulatedGps(initialSimGps, force: true);
      setState(() => _debugJoystickEnabled = true);
      _startDebugMovementLoop();
    } else {
      _stopDebugTick();
      _debugDir = Offset.zero;
      LocationService.setSimulated(false);
      _lastSimUploadAt = null;
      _simUploadInProgress = false;
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
    LocationService.setSimulated(false);
    _stopDebugTick();
    _gpsSub?.cancel();
    _busSub?.cancel();
    _studentsSub?.cancel();
    unawaited(_uploader.stop());
    _trafficEta.dispose();
    _mapController.dispose();
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
      _mapController.move(
        center: LatLng(pos.latitude, pos.longitude),
        zoom: 15,
      );
      return;
    }
    final pin = fleetBusMapPosition(gps: _gps, bus: _bus);
    if (pin == null) return;
    setState(() => _followBus = true);
    _mapController.move(center: pin, zoom: 15);
  }

  void _zoomIn() {
    final center = _mapController.lastRequestedCenter ?? _fallbackCenter;
    _mapController.move(center: center, zoom: _zoom + 1);
  }

  void _zoomOut() {
    final center = _mapController.lastRequestedCenter ?? _fallbackCenter;
    _mapController.move(center: center, zoom: _zoom - 1);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
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
            final googleRoutePoints = (planned == null)
                ? const <RouteWaypoint>[]
                : planned.googleWaypointsForTrip(tripDir);
            final stopMarkers = <SchoolWayMapMarker>[];
            final orderedStops = planned == null
                ? const <AssignedRouteStop>[]
                : buildAssignedRouteStops(
                    route: planned,
                    busId: widget.activeSession!.busId,
                    direction: tripDir,
                    students: assignedStudents,
                    serviceStopRouteIndices:
                        widget.activeSession!.serviceStopRouteIndices,
                  );

            for (var i = 0; i < orderedStops.length; i++) {
              final assignedStop = orderedStops[i];
              final stop = assignedStop.waypoint;
              final count = assignedStop.students.length;

              stopMarkers.add(
                SchoolWayMapMarker(
                  id: 'driver-stop-${assignedStop.routeStopIndex}',
                  latitude: stop.latitude,
                  longitude: stop.longitude,
                  width: 60,
                  height: 44,
                  alignment: Alignment.bottomCenter,
                  child: buildStopNumberWidget(
                    number: assignedStop.serviceStopNumber,
                    studentCount: count,
                  ),
                ),
              );
            }

            return SafeArea(
              child: ValueListenableBuilder<TrafficEtaState>(
                valueListenable: _trafficEta.state,
                builder: (context, trafficState, _) {
                  final trafficPolyline =
                      trafficState.isAvailable && trafficState.snapshot != null
                      ? trafficState.snapshot!.decodeWaypoints()
                      : const <RouteWaypoint>[];
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: SchoolWayMap(
                          controller: _mapController,
                          initialCenter: center,
                          initialZoom: 14,
                          onUserPan: (lat, lng) {
                            if (_followBus) setState(() => _followBus = false);
                          },
                          onCameraChanged: (lat, lng, zoom) => _zoom = zoom,
                          markers: [
                            ...stopMarkers,
                            if (_myLocation != null)
                              buildMyLocationMarker(
                                id: 'driver-my-location',
                                position: _myLocation!,
                              ),
                            if (pin != null)
                              SchoolWayMapMarker(
                                id: 'driver-bus-${widget.activeSession!.busId}',
                                latitude: pin.latitude,
                                longitude: pin.longitude,
                                width: 72,
                                height: 56,
                                alignment: Alignment.bottomCenter,
                                child: buildFleetBusMarkerWidget(
                                  busId: widget.activeSession!.busId,
                                  busLabel: _bus?.busNumber ?? 'BUS',
                                ),
                              ),
                          ],
                          polylines: [
                            if (googleRoutePoints.length >= 2)
                              SchoolWayMapPolyline(
                                id: 'driver-route',
                                points: googleRoutePoints,
                                strokeWidth: 4,
                                color: SchoolWayTheme.primary.withValues(
                                  alpha: 0.75,
                                ),
                              ),
                            if (trafficPolyline.length >= 2)
                              SchoolWayMapPolyline(
                                id: 'driver-traffic-eta',
                                points: trafficPolyline,
                                strokeWidth: 5,
                                color: SchoolWayTheme.violet,
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TrafficEtaChip(state: trafficState),
                            if (planned != null &&
                                planned.editableStops.length >= 2 &&
                                googleRoutePoints.isEmpty)
                              Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: RouteGeometryMissingBanner(),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerSignal: (_) {},
                          child: Container(
                            margin: const EdgeInsets.all(16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: SchoolWayTheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: SchoolWayTheme.text.withValues(
                                    alpha: 0.1,
                                  ),
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
                                      strings.livePosition,
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
                                  strings.speed,
                                  _gps != null
                                      ? '${_gps!.speed.toStringAsFixed(0)} km/h'
                                      : '—',
                                ),
                                SizedBox(height: 8),
                                _buildLocationRow(
                                  Icons.gps_fixed,
                                  strings.gps,
                                  _gps != null
                                      ? strings.liveFix
                                      : (pin != null
                                            ? strings.savedOnBus
                                            : strings.waitingForFix),
                                ),
                                SizedBox(height: 8),
                                _buildLocationRow(
                                  Icons.update,
                                  strings.lastUpdated,
                                  fleetBusLastSeenLabel(gps: _gps, bus: _bus),
                                ),
                                if (_debugJoystickEnabled ||
                                    _gps?.isSimulated == true) ...[
                                  SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: SimulatedLocationBadge(),
                                  ),
                                ],
                                SizedBox(height: 8),
                                Text(
                                  _debugJoystickEnabled
                                      ? strings.busSimulationActiveDescription
                                      : strings.gpsUploadsEverySeconds(
                                          AppConfig.gpsUploadInterval.inSeconds,
                                        ),
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
                      ),
                      Positioned(
                        top: 40,
                        right: 16,
                        child: Column(
                          children: [
                            _buildMapControlButton(
                              Icons.my_location,
                              _debugJoystickEnabled
                                  ? strings.locateDeviceGps
                                  : strings.recenterOnBus,
                              (pin != null || _debugJoystickEnabled)
                                  ? () => unawaited(_handleRecenter())
                                  : null,
                            ),
                            SizedBox(height: 8),
                            _buildMapControlButton(
                              Icons.add,
                              strings.zoomIn,
                              _zoomIn,
                            ),
                            SizedBox(height: 8),
                            _buildMapControlButton(
                              Icons.remove,
                              strings.zoomOut,
                              _zoomOut,
                            ),
                            if (widget.activeSession != null) ...[
                              SizedBox(height: 8),
                              _buildMapControlButton(
                                Icons.science_outlined,
                                strings.busSimulation,
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
                            semanticLabel:
                                strings.dragTheControllerToMoveTheBus,
                            onDirectionChanged: _onDebugDirection,
                          ),
                        ),
                    ],
                  );
                },
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
                Icons.map_outlined,
                size: 100,
                color: SchoolWayTheme.muted,
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: Text(
                AppLocalizations.of(context).gpsTrackingDisabled,
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
                AppLocalizations.of(context).startARouteSessionToShareLive,
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
}
