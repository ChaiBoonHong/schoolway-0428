import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/fleet_bus_colors.dart';
import 'package:schoolway/core/fleet_bus_position.dart';
import 'package:schoolway/core/widgets/fleet_bus_marker.dart';
import 'package:schoolway/core/widgets/osm_map_attribution.dart';
import 'package:schoolway/core/widgets/osm_map_tile_layer.dart';
import 'package:schoolway/core/latency_tracker.dart';
import 'package:schoolway/models/models.dart';

import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/services/location_service.dart';
import 'package:schoolway/services/eta_geofence_service.dart';

class ParentLiveMapTab extends StatefulWidget {
  const ParentLiveMapTab({super.key});

  @override
  State<ParentLiveMapTab> createState() => _ParentLiveMapTabState();
}

class _ParentLiveMapTabState extends State<ParentLiveMapTab>
    with SingleTickerProviderStateMixin {
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final MapController _mapController = MapController();
  bool _locatingSelf = false;
  LatLng? _myLocation;
  String? _selectedBusId;
  late final AnimationController _pulseController;

  // Stable stream references — prevents re-subscription (and momentary null
  // snapshots) whenever a parent StreamBuilder rebuilds.
  final Stream<Map<String, GpsTracking>> _gpsStream =
      FirebaseService.getAllGpsTracking();
  final Stream<List<RouteSession>> _sessionStream =
      FirebaseService.watchAllActiveRouteSessions();
  final Stream<List<PlannedRoute>> _plannedRouteStream =
      FirebaseService.getPlannedRoutes();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    final c = _mapController;
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    super.dispose();
  }

  void _moveTo(LatLng p, {double zoom = 15}) {
    try {
      _mapController.move(p, zoom);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'data',
        'Malformed or unavailable optional data was ignored.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static LatLng _mapCenterFromPoints(List<LatLng> pts) {
    if (pts.isEmpty) return LatLng(3.1390, 101.6869);
    final lat = pts.map((e) => e.latitude).reduce((a, b) => a + b) / pts.length;
    final lng =
        pts.map((e) => e.longitude).reduce((a, b) => a + b) / pts.length;
    return LatLng(lat, lng);
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

  Widget _buildMapControlButton(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool loading = false,
  }) {
    return Material(
      color: SchoolWayTheme.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: loading
          ? Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: SchoolWayTheme.primary,
                ),
              ),
            )
          : IconButton(
              icon: Icon(icon, color: SchoolWayTheme.primary),
              onPressed: onPressed,
              tooltip: tooltip,
            ),
    );
  }

  Future<void> _centerOnMyLocation() async {
    if (_locatingSelf) return;
    setState(() => _locatingSelf = true);
    try {
      final pos = await LocationService.getCurrentPositionBestEffort();
      if (!mounted) return;
      if (pos == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              ).locationPermissionIsRequiredToShowYour,
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: SchoolWayTheme.warning,
          ),
        );
        return;
      }
      final myLoc = LatLng(pos.latitude, pos.longitude);
      setState(() => _myLocation = myLoc);
      _moveTo(myLoc, zoom: 15);
    } finally {
      if (mounted) setState(() => _locatingSelf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUserId == null) {
      return Center(child: Text(AppLocalizations.of(context).pleaseSignIn));
    }

    return StreamBuilder<List<Student>>(
      stream: FirebaseService.getStudentsByParentAuthUid(_currentUserId),
      builder: (context, studentSnapshot) {
        if (studentSnapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: SchoolWayTheme.primary),
          );
        }

        if (studentSnapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${studentSnapshot.error}',
              style: TextStyle(fontFamily: 'Lexend'),
            ),
          );
        }

        final students = studentSnapshot.data ?? [];

        if (students.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.family_restroom,
                  size: 64,
                  color: SchoolWayTheme.accent,
                ),
                SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context).noStudentsFound,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  AppLocalizations.of(
                    context,
                  ).contactKindergartenAdminToAddYourChild,
                  style: TextStyle(fontFamily: 'Lexend', fontSize: 14),
                ),
              ],
            ),
          );
        }

        final busIds = <String>[];
        final seen = <String>{};
        for (final s in students) {
          final bid = s.assignedBusId;
          if (bid != null && bid.isNotEmpty && seen.add(bid)) {
            busIds.add(bid);
          }
        }

        if (busIds.isEmpty) {
          return Center(
            child: Text(
              AppLocalizations.of(context).noBusAssignedYet,
              style: TextStyle(fontFamily: 'Lexend'),
            ),
          );
        }

        return StreamBuilder<List<RouteSession>>(
          stream: _sessionStream,
          builder: (context, sessionSnap) {
            return StreamBuilder<Map<String, GpsTracking>>(
              stream: _gpsStream,
              builder: (context, gpsSnap) {
                final activeByBus = <String, RouteSession>{};
                for (final sess in sessionSnap.data ?? []) {
                  activeByBus[sess.busId] = sess;
                }
                final gpsByBus = gpsSnap.data ?? {};
                for (final gps in gpsByBus.values) {
                  LatencyTracker.recordSample(gps.timestamp);
                }

                return StreamBuilder<Map<String, Bus?>>(
                  stream: FirebaseService.watchBusesByIds(busIds),
                  builder: (context, busSnap) {
                    final busesById = busSnap.data ?? {};
                    final pts = <LatLng>[];
                    for (final bid in busIds) {
                      final p = fleetBusMapPosition(
                        gps: gpsByBus[bid],
                        bus: busesById[bid],
                      );
                      if (p != null) pts.add(p);
                    }
                    final center = _mapCenterFromPoints(pts);
                    final zoom = busIds.length > 1 ? 12.0 : 14.0;

                    final markers = <Marker>[];
                    for (final bid in busIds) {
                      final p = fleetBusMapPosition(
                        gps: gpsByBus[bid],
                        bus: busesById[bid],
                      );
                      if (p == null) continue;
                      markers.add(
                        buildFleetBusMarker(
                          point: p,
                          busId: bid,
                          busLabel: busesById[bid]?.busNumber ?? 'BUS',
                        ),
                      );
                    }

                    return StreamBuilder<List<PlannedRoute>>(
                      stream: _plannedRouteStream,
                      builder: (context, plannedSnap) {
                        final plannedById = <String, PlannedRoute>{};
                        for (final route
                            in plannedSnap.data ?? const <PlannedRoute>[]) {
                          plannedById[route.id] = route;
                        }

                        final selectedBusId = _selectedBusId;
                        Polyline? selectedRoutePolyline;
                        final selectedStopMarkers = <Marker>[];
                        final geofenceCircles = <CircleMarker>[];
                        if (selectedBusId != null) {
                          final session = activeByBus[selectedBusId];
                          final selectedBus = busesById[selectedBusId];
                          final routeId =
                              session?.routeId ?? selectedBus?.assignedRouteId;
                          if (routeId != null && routeId.trim().isNotEmpty) {
                            final planned = plannedById[routeId];
                            if (planned != null &&
                                planned.waypoints.length >= 2) {
                              final tripDirection =
                                  session?.tripDirection ??
                                  TripDirection.toSchool;
                              final routeWaypoints = planned.waypointsForTrip(
                                tripDirection,
                              );
                              selectedRoutePolyline = Polyline(
                                points: routeWaypoints
                                    .map((w) => LatLng(w.latitude, w.longitude))
                                    .toList(),
                                strokeWidth: 5,
                                color: fleetBusAccentColor(
                                  selectedBusId,
                                ).withValues(alpha: 0.72),
                              );

                              final studentsOnSelectedBus = students.where(
                                (s) => s.assignedBusId == selectedBusId,
                              );
                              final assignedStops = buildAssignedRouteStops(
                                route: planned,
                                busId: selectedBusId,
                                direction: tripDirection,
                                students: studentsOnSelectedBus,
                                serviceStopRouteIndices:
                                    session?.serviceStopRouteIndices ??
                                    const [],
                              );

                              final gps = gpsByBus[selectedBusId];
                              final speedKmh = gps == null
                                  ? 30.0
                                  : EtaGeofenceService.smoothedSpeedKmh(
                                      key: session?.id ?? selectedBusId,
                                      speedKmh: gps.speed,
                                      sampledAt: gps.timestamp,
                                    );

                              for (final assignedStop in assignedStops) {
                                final stop = assignedStop.waypoint;
                                final stopPos = LatLng(
                                  stop.latitude,
                                  stop.longitude,
                                );

                                geofenceCircles.add(
                                  CircleMarker(
                                    point: stopPos,
                                    color: Color(
                                      0xFF00B4D8,
                                    ).withValues(alpha: 0.2),
                                    borderStrokeWidth: 2,
                                    borderColor: Color(
                                      0xFF00B4D8,
                                    ).withValues(alpha: 0.5),
                                    useRadiusInMeter: true,
                                    radius: 200, // 200 meters geofence
                                  ),
                                );

                                // Pulse ring
                                geofenceCircles.add(
                                  CircleMarker(
                                    point: stopPos,
                                    color: SchoolWayTheme.transparent,
                                    borderStrokeWidth: 2,
                                    borderColor: SchoolWayTheme.accent
                                        .withValues(
                                          alpha: _pulseController.value * 0.8,
                                        ),
                                    useRadiusInMeter: true,
                                    radius: 200 + (_pulseController.value * 50),
                                  ),
                                );

                                int? etaMinutes;
                                if (gps != null) {
                                  etaMinutes =
                                      EtaGeofenceService.calculateRouteEtaMinutes(
                                        currentPos: LatLng(
                                          gps.latitude,
                                          gps.longitude,
                                        ),
                                        routeWaypoints: routeWaypoints,
                                        targetStop: stop,
                                        speedKmh: speedKmh,
                                      );
                                }

                                selectedStopMarkers.add(
                                  Marker(
                                    point: stopPos,
                                    width: 80,
                                    height: 60,
                                    alignment: Alignment.topCenter,
                                    child: Column(
                                      children: [
                                        if (etaMinutes != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: SchoolWayTheme.surface
                                                  .withValues(alpha: 0.9),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: SchoolWayTheme.warning,
                                                width: 1,
                                              ),
                                            ),
                                            child: Text(
                                              '~$etaMinutes min',
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
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: SchoolWayTheme.warning,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: SchoolWayTheme.surface,
                                              width: 2,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${assignedStop.serviceStopNumber}',
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
                              if (routeWaypoints.isNotEmpty) {
                                final finalStop = routeWaypoints.last;
                                selectedStopMarkers.add(
                                  Marker(
                                    point: LatLng(
                                      finalStop.latitude,
                                      finalStop.longitude,
                                    ),
                                    width: 40,
                                    height: 40,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: SchoolWayTheme.successBright,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: SchoolWayTheme.surface,
                                          width: 2,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.flag,
                                        size: 18,
                                        color: SchoolWayTheme.surface,
                                      ),
                                    ),
                                  ),
                                );
                              }
                            }
                          }
                        }

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter: center,
                                  initialZoom: zoom,
                                ),
                                children: [
                                  OsmMapTileLayer(),
                                  if (geofenceCircles.isNotEmpty)
                                    AnimatedBuilder(
                                      animation: _pulseController,
                                      builder: (context, child) {
                                        final pulseCircles = <CircleMarker>[
                                          ...geofenceCircles,
                                        ];
                                        // add pulse
                                        for (final stop
                                            in selectedStopMarkers) {
                                          pulseCircles.add(
                                            CircleMarker(
                                              point: stop.point,
                                              color: SchoolWayTheme.transparent,
                                              borderStrokeWidth: 2,
                                              borderColor: SchoolWayTheme.accent
                                                  .withValues(
                                                    alpha:
                                                        (1.0 -
                                                            _pulseController
                                                                .value) *
                                                        0.8,
                                                  ),
                                              useRadiusInMeter: true,
                                              radius:
                                                  200 +
                                                  (_pulseController.value *
                                                      100),
                                            ),
                                          );
                                        }
                                        return CircleLayer(
                                          circles: pulseCircles,
                                        );
                                      },
                                    ),
                                  if (selectedRoutePolyline != null)
                                    PolylineLayer(
                                      polylines: [selectedRoutePolyline],
                                    ),
                                  if (selectedStopMarkers.isNotEmpty)
                                    MarkerLayer(markers: selectedStopMarkers),
                                  MarkerLayer(
                                    markers: [
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
                                      ...markers,
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
                              top: 40,
                              right: 16,
                              child: Column(
                                children: [
                                  _buildMapControlButton(
                                    Icons.my_location,
                                    'My location',
                                    _locatingSelf ? null : _centerOnMyLocation,
                                    loading: _locatingSelf,
                                  ),
                                  SizedBox(height: 8),
                                  _buildMapControlButton(
                                    Icons.add,
                                    'Zoom in',
                                    _zoomIn,
                                  ),
                                  SizedBox(height: 8),
                                  _buildMapControlButton(
                                    Icons.remove,
                                    'Zoom out',
                                    _zoomOut,
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              bottom: 16,
                              left: 16,
                              right: 16,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxHeight: 240),
                                child: Material(
                                  color: SchoolWayTheme.transparent,
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (busIds.length > 1)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8,
                                            ),
                                            child: Text(
                                              '${busIds.length} buses for your children',
                                              style: TextStyle(
                                                fontFamily: 'Lexend',
                                                fontSize: 12,
                                                color: SchoolWayTheme.blueGrey,
                                              ),
                                            ),
                                          ),
                                        for (
                                          var i = 0;
                                          i < busIds.length;
                                          i++
                                        ) ...[
                                          if (i > 0) SizedBox(height: 10),
                                          () {
                                            int? minEta;
                                            final busId = busIds[i];
                                            final bus = busesById[busId];
                                            final gps = gpsByBus[busId];
                                            final studentsOnBus = students
                                                .where(
                                                  (s) =>
                                                      s.assignedBusId == busId,
                                                )
                                                .toList();
                                            final routeIsLive = activeByBus
                                                .containsKey(busId);

                                            if (bus != null &&
                                                gps != null &&
                                                routeIsLive) {
                                              final session =
                                                  activeByBus[busId];
                                              final routeId =
                                                  session?.routeId ??
                                                  bus.assignedRouteId;
                                              final planned = routeId == null
                                                  ? null
                                                  : plannedById[routeId];
                                              if (session != null &&
                                                  planned != null) {
                                                final assignedStops =
                                                    buildAssignedRouteStops(
                                                      route: planned,
                                                      busId: busId,
                                                      direction:
                                                          session.tripDirection,
                                                      students: studentsOnBus,
                                                      serviceStopRouteIndices:
                                                          session
                                                              .serviceStopRouteIndices,
                                                    );
                                                final routeWaypoints = planned
                                                    .waypointsForTrip(
                                                      session.tripDirection,
                                                    );
                                                final speedKmh =
                                                    EtaGeofenceService.smoothedSpeedKmh(
                                                      key: session.id,
                                                      speedKmh: gps.speed,
                                                      sampledAt: gps.timestamp,
                                                    );
                                                for (final assignedStop
                                                    in assignedStops) {
                                                  final eta =
                                                      EtaGeofenceService.calculateRouteEtaMinutes(
                                                        currentPos: LatLng(
                                                          gps.latitude,
                                                          gps.longitude,
                                                        ),
                                                        routeWaypoints:
                                                            routeWaypoints,
                                                        targetStop: assignedStop
                                                            .waypoint,
                                                        speedKmh: speedKmh,
                                                      );
                                                  if (eta != null &&
                                                      (minEta == null ||
                                                          eta < minEta)) {
                                                    minEta = eta;
                                                  }
                                                }
                                              }
                                            }

                                            return _ParentBusSummaryCard(
                                              accentColor: fleetBusAccentColor(
                                                busId,
                                              ),
                                              bus: bus,
                                              studentsOnBus: studentsOnBus,
                                              gps: gps,
                                              routeIsLive: routeIsLive,
                                              etaMinutes: minEta,
                                              onShowOnMap: () {
                                                final p = fleetBusMapPosition(
                                                  gps: gps,
                                                  bus: bus,
                                                );
                                                if (p == null) return null;
                                                return () {
                                                  setState(
                                                    () =>
                                                        _selectedBusId = busId,
                                                  );
                                                  _moveTo(p, zoom: 15);
                                                };
                                              }(),
                                            );
                                          }(),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ParentBusSummaryCard extends StatelessWidget {
  const _ParentBusSummaryCard({
    required this.accentColor,
    required this.bus,
    required this.studentsOnBus,
    required this.gps,
    required this.routeIsLive,
    this.etaMinutes,
    required this.onShowOnMap,
  });

  final Color accentColor;
  final Bus? bus;
  final List<Student> studentsOnBus;
  final GpsTracking? gps;
  final bool routeIsLive;
  final int? etaMinutes;
  final VoidCallback? onShowOnMap;

  @override
  Widget build(BuildContext context) {
    final busLabel = bus?.busNumber ?? 'Bus';
    final childNames = studentsOnBus.map((s) => s.fullName).join(', ');
    final simulated =
        gps?.isSimulated ?? bus?.lastLocation?.isSimulated ?? false;

    return Material(
      color: SchoolWayTheme.transparent,
      child: InkWell(
        onTap: onShowOnMap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SchoolWayTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: SchoolWayTheme.text.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: routeIsLive
                          ? SchoolWayTheme.success
                          : SchoolWayTheme.muted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.directions_bus, color: accentColor, size: 20),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      busLabel,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: SchoolWayTheme.navy,
                      ),
                    ),
                  ),
                  if (onShowOnMap != null)
                    Icon(
                      Icons.open_in_full,
                      size: 18,
                      color: SchoolWayTheme.primary,
                    ),
                ],
              ),
              if (childNames.isNotEmpty) ...[
                SizedBox(height: 6),
                Text(
                  childNames,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13,
                    color: SchoolWayTheme.blueGrey,
                  ),
                ),
              ],
              if (simulated) ...[
                SizedBox(height: 6),
                Chip(
                  avatar: Icon(Icons.science_outlined, size: 16),
                  label: Text(
                    AppLocalizations.of(context).simulatedPosition,
                    style: TextStyle(fontFamily: 'Lexend'),
                  ),
                ),
              ],
              if (fleetBusHasMapPosition(gps: gps, bus: bus)) ...[
                SizedBox(height: 6),
                Text(
                  routeIsLive
                      ? 'Tap to show this bus on the map'
                      : 'Last known position (route not active)',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12,
                    color: SchoolWayTheme.accent,
                  ),
                ),
              ],
              SizedBox(height: 8),
              Text(
                routeIsLive
                    ? 'Live · Last update: ${fleetBusLastSeenLabel(gps: gps, bus: bus)}'
                    : (fleetBusHasMapPosition(gps: gps, bus: bus)
                          ? 'Last seen: ${fleetBusLastSeenLabel(gps: gps, bus: bus)}'
                          : 'No tracking data'),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 14,
                  color: SchoolWayTheme.primary,
                ),
              ),
              if (bus?.currentRoute != null) ...[
                SizedBox(height: 4),
                Text(
                  'Route: ${bus!.currentRoute}',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14,
                    color: SchoolWayTheme.primary,
                  ),
                ),
              ],
              if (etaMinutes != null) ...[
                SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: SchoolWayTheme.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: SchoolWayTheme.warning),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer,
                        size: 16,
                        color: SchoolWayTheme.warning,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'ETA to stop: ~$etaMinutes min',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: SchoolWayTheme.warning,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
