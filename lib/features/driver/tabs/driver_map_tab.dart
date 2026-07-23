import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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
  GpsTracking? _gps;
  Bus? _bus;
  LatLng? _myLocation;
  bool _locatingSelf = false;
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
      unawaited(_syncSession(widget.activeSession).then((_) {
        if (mounted && widget.mapTabActive) _scheduleMapTileRefresh();
      }));
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
    } catch (_) {}
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
      } catch (_) {}
      _scheduleMapTileRefresh();
    });
  }

  PlannedRoute? _plannedRoute;
  bool _followBus = true;

  Future<void> _syncSession(RouteSession? session) async {
    _gpsSub?.cancel();
    _gpsSub = null;
    _busSub?.cancel();
    _busSub = null;
    _stopDebugTick();
    if (!mounted) return;
    setState(() {
      _gps = null;
      _bus = null;
      _centeredOnFirstFix = false;
      _debugJoystickEnabled = false;
      _plannedRoute = null;
    });

    StationaryBusDetector().stop();
    await _uploader.stop();
    if (!mounted) return;

    if (session == null) {
      EtaGeofenceService.clearSession('');
      return;
    }
    
    if (session.routeId != null) {
      _plannedRoute = await FirebaseService.getPlannedRouteById(session.routeId!);
    }

    await _uploader.start(busId: session.busId, sessionId: session.id);
    StationaryBusDetector().start(busId: session.busId, sessionId: session.id);
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
          if (_plannedRoute != null) {
             final stops = _plannedRoute!.editableStopsForTrip(session.tripDirection);
             final event = await EtaGeofenceService.processLocationUpdate(
               sessionId: session.id,
               currentPos: LatLng(gps.latitude, gps.longitude),
               stops: stops,
             );
             if (event != null && mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(
                   content: Text(
                     '${event.type == GeofenceEventType.atStop ? "Arrived at" : "Departed"} stop ${event.stopIndex + 1}',
                     style: const TextStyle(fontFamily: 'Lexend'),
                   ),
                   backgroundColor: const Color(0xFF00B4D8),
                   duration: const Duration(seconds: 3),
                 ),
               );
             }
          }
        }
      },
    );

    _busSub = FirebaseService.watchBusById(session.busId).listen(
      (bus) {
        if (!mounted) return;
        setState(() => _bus = bus);
        _maybeCenterOnFirstFix();
      },
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

    _debugTick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !_debugJoystickEnabled) return;
      final s = widget.activeSession;
      if (s == null) return;
      final d = _debugDir;
      final now = DateTime.now();
      // Broadcast to Firestore at most every 500 ms — keeps admin/parent in sync
      // while staying well within Firestore's per-document write rate limit.
      final canWriteFirestore = _debugLastFirestoreWrite == null ||
          now.difference(_debugLastFirestoreWrite!).inMilliseconds >= 500;

      if (d.distance < 0.008) {
        // Joystick at rest — emit a stopped update so speed reads 0 km/h.
        if (_gps != null && _gps!.speed > 0) {
          final stopped = GpsTracking(
            busId: s.busId,
            latitude: _simLat,
            longitude: _simLng,
            speed: 0,
            heading: _gps!.heading,
            accuracy: 4,
            timestamp: now,
            sessionId: s.id,
          );
          setState(() => _gps = stopped);
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
      );

      // Update local state immediately so the driver map pin moves without
      // waiting for the Firestore round-trip.
      setState(() => _gps = fakeGps);

      // Broadcast to Firestore at most once per second so admin / parent views
      // stay in sync without hitting Firestore's per-document write rate limit.
      if (canWriteFirestore) {
        _debugLastFirestoreWrite = now;
        unawaited(FirebaseService.updateGpsLocation(fakeGps));
      }
    });
  }

  Future<void> _setDebugJoystick(bool enabled) async {
    if (!kDebugMode) return;
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
      );

      await _uploader.start(busId: session.busId, sessionId: session.id);
    }
  }

  @override
  void dispose() {
    _stopDebugTick();
    _gpsSub?.cancel();
    _busSub?.cancel();
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
          const SnackBar(
            content: Text(
              'Could not get your GPS location. Check permission and that location is on.',
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: Color(0xFFFF9800),
          ),
        );
        return;
      }
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      try {
        _mapController.move(LatLng(pos.latitude, pos.longitude), 15);
      } catch (_) {}
      return;
    }
    final pin = fleetBusMapPosition(gps: _gps, bus: _bus);
    if (pin == null) return;
    try {
      _mapController.move(pin, 15);
    } catch (_) {}
  }

  Future<void> _showMyLocation() async {
    if (_locatingSelf) return;
    setState(() => _locatingSelf = true);
    try {
      final pos = await LocationService.getCurrentPositionBestEffort();
      if (!mounted) return;
      if (pos == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not get your GPS location. Check permission and that location is on.',
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: Color(0xFFFF9800),
          ),
        );
        return;
      }
      final myLoc = LatLng(pos.latitude, pos.longitude);
      setState(() => _myLocation = myLoc);
      try {
        _mapController.move(myLoc, 15);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _locatingSelf = false);
    }
  }

  void _zoomIn() {
    try {
      final c = _mapController.camera;
      _mapController.move(c.center, (c.zoom + 1).clamp(3, 19));
    } catch (_) {}
  }

  void _zoomOut() {
    try {
      final c = _mapController.camera;
      _mapController.move(c.center, (c.zoom - 1).clamp(3, 19));
    } catch (_) {}
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
      stream: FirebaseService.getAllStudents(),
      builder: (context, studentSnap) {
        final allStudents = studentSnap.data ?? const <Student>[];
        final sessionBusId = widget.activeSession?.busId;
        final assignedStudents = allStudents.where((s) => s.assignedBusId == sessionBusId).toList();

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
        final geofenceCircles = <CircleMarker>[];
        final orderedStops = planned == null
            ? const <RouteWaypoint>[]
            : planned.editableStopsForTrip(tripDir);

        for (var i = 0; i < orderedStops.length; i++) {
          final stop = orderedStops[i];
          final stopPos = LatLng(stop.latitude, stop.longitude);
          geofenceCircles.add(
            CircleMarker(
              point: stopPos,
              color: const Color(0xFF00B4D8).withValues(alpha: 0.2),
              borderStrokeWidth: 2,
              borderColor: const Color(0xFF00B4D8).withValues(alpha: 0.5),
              useRadiusInMeter: true,
              radius: 200, // 200 meters geofence
            ),
          );
          
          final studentsAtStop = assignedStudents.where((s) => s.assignedStopName == 'Stop ${i + 1}').toList();
          final count = studentsAtStop.length;
          
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF00B4D8), width: 1),
                      ),
                      child: Text(
                        '$count student${count > 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF03045E),
                        ),
                      ),
                    ),
                  const SizedBox(height: 2),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B4D8),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        color: Colors.white,
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
                    }
                  ),
                  children: [
                    const OsmMapTileLayer(),
                    if (geofenceCircles.isNotEmpty)
                      CircleLayer(circles: geofenceCircles),
                    if (routePolylinePoints.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: routePolylinePoints,
                            strokeWidth: 4,
                            color: const Color(0xFF0077B6).withValues(alpha: 0.75),
                          ),
                        ],
                      ),
                    if (pin != null || _myLocation != null || stopMarkers.isNotEmpty)
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
                                  color: const Color(0xFF2196F3),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
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
              const Positioned(
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.location_on, color: Color(0xFF0077B6), size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Live position',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF03045E),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildLocationRow(
                        Icons.speed,
                        'Speed',
                        _gps != null
                            ? '${_gps!.speed.toStringAsFixed(0)} km/h'
                            : '—',
                      ),
                      const SizedBox(height: 8),
                      _buildLocationRow(
                        Icons.gps_fixed,
                        'GPS',
                        _gps != null
                            ? 'Live fix'
                            : (pin != null ? 'Saved on bus' : 'Waiting for fix…'),
                      ),
                      const SizedBox(height: 8),
                      _buildLocationRow(
                        Icons.update,
                        'Last updated',
                        fleetBusLastSeenLabel(gps: _gps, bus: _bus),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _debugJoystickEnabled
                            ? 'Debug joystick: fake position (no device GPS)'
                            : 'Uploads every ${AppConfig.gpsUploadInterval.inSeconds}s',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12,
                          color: Colors.blueGrey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (kDebugMode)
                Positioned(
                  left: 12,
                  bottom: 200,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.bug_report_outlined,
                                    size: 18, color: Color(0xFF0077B6)),
                                const SizedBox(width: 8),
                                const Text(
                                  'Debug drive',
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: Color(0xFF03045E),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Switch(
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  value: _debugJoystickEnabled,
                                  onChanged: (v) =>
                                      unawaited(_setDebugJoystick(v)),
                                ),
                              ],
                            ),
                            if (_debugJoystickEnabled) ...[
                              const SizedBox(height: 4),
                              const Text(
                                'Drag the stick to move the bus on the map.',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 11,
                                  color: Colors.blueGrey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: DebugBusJoystick(
                                  onDirectionChanged: _onDebugDirection,
                                ),
                              ),
                            ],
                          ],
                        ),
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
                      _followBus ? Icons.explore : Icons.explore_off,
                      'Follow Bus',
                      () {
                        setState(() {
                          _followBus = !_followBus;
                          if (_followBus) {
                             final p = fleetBusMapPosition(gps: _gps, bus: _bus);
                             if (p != null) {
                               _mapController.move(p, _mapController.camera.zoom);
                             }
                          }
                        });
                      },
                      isActive: _followBus,
                    ),
                    const SizedBox(height: 8),
                    _buildMapControlButton(
                      Icons.my_location,
                      _debugJoystickEnabled
                          ? 'Locate me (device GPS)'
                          : 'Re-center on bus',
                      (pin != null || _debugJoystickEnabled)
                          ? () => unawaited(_handleRecenter())
                          : null,
                    ),
                    const SizedBox(height: 8),
                    _buildMapControlButton(
                      Icons.person_pin_circle_outlined,
                      'Show my location',
                      _locatingSelf ? null : () => unawaited(_showMyLocation()),
                    ),
                    const SizedBox(height: 8),
                    _buildMapControlButton(Icons.add, 'Zoom in', _zoomIn),
                    const SizedBox(height: 8),
                    _buildMapControlButton(Icons.remove, 'Zoom out', _zoomOut),
                  ],
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
        Icon(icon, size: 16, color: const Color(0xFF0077B6)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14,
            color: Color(0xFF0077B6),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF03045E),
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
  }) {
    return Material(
      color: isActive ? const Color(0xFF0077B6) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: IconButton(
        icon: Icon(icon, color: isActive ? Colors.white : const Color(0xFF0077B6)),
        onPressed: onPressed,
        tooltip: tooltip,
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
                color: Colors.grey.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.map_outlined,
                size: 100,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'GPS Tracking Disabled',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Start a route session to share live location with parents',
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
}
