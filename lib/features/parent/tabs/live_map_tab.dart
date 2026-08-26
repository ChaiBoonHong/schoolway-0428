import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/fleet_bus_colors.dart';
import 'package:schoolway/core/fleet_bus_position.dart';
import 'package:schoolway/core/map/map_markers.dart';
import 'package:schoolway/core/map/schoolway_map.dart';
import 'package:schoolway/core/map/schoolway_map_controller.dart';
import 'package:schoolway/core/widgets/route_geometry_missing_banner.dart';
import 'package:schoolway/core/widgets/traffic_eta_chip.dart';
import 'package:schoolway/core/latency_tracker.dart';
import 'package:schoolway/models/models.dart';

import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/services/location_service.dart';
import 'package:schoolway/services/traffic_eta_service.dart';

class ParentLiveMapTab extends StatefulWidget {
  const ParentLiveMapTab({super.key});

  @override
  State<ParentLiveMapTab> createState() => _ParentLiveMapTabState();
}

class _ParentLiveMapTabState extends State<ParentLiveMapTab>
    with SingleTickerProviderStateMixin {
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final SchoolWayMapController _mapController = SchoolWayMapController();
  bool _locatingSelf = false;
  LatLng? _myLocation;
  String? _selectedBusId;
  double _zoom = 14;
  late final AnimationController _pulseController;
  final TrafficEtaService _trafficEta = TrafficEtaService();
  String? _trafficEtaSessionId;

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
    _trafficEta.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _moveTo(LatLng p, {double zoom = 15}) {
    _mapController.move(center: p, zoom: zoom);
  }

  void _onCameraChanged(double latitude, double longitude, double zoom) {
    _zoom = zoom;
  }

  static LatLng _mapCenterFromPoints(List<LatLng> pts) {
    if (pts.isEmpty) return LatLng(3.1390, 101.6869);
    final lat = pts.map((e) => e.latitude).reduce((a, b) => a + b) / pts.length;
    final lng =
        pts.map((e) => e.longitude).reduce((a, b) => a + b) / pts.length;
    return LatLng(lat, lng);
  }

  void _zoomIn() {
    _mapController.move(
      center:
          _mapController.lastRequestedCenter ?? const LatLng(3.1390, 101.6869),
      zoom: _zoom + 1,
    );
  }

  void _zoomOut() {
    _mapController.move(
      center:
          _mapController.lastRequestedCenter ?? const LatLng(3.1390, 101.6869),
      zoom: _zoom - 1,
    );
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

                // Auto-select first bus with active session if none selected
                if (_selectedBusId == null && activeByBus.isNotEmpty) {
                  final firstActiveBusId = activeByBus.keys.first;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _selectedBusId = firstActiveBusId);
                    }
                  });
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
                    final selectedSessionForTraffic = _selectedBusId != null
                        ? activeByBus[_selectedBusId]
                        : null;
                    if (_trafficEtaSessionId != selectedSessionForTraffic?.id) {
                      _trafficEtaSessionId = selectedSessionForTraffic?.id;
                      if (selectedSessionForTraffic != null) {
                        _trafficEta.start(selectedSessionForTraffic.id);
                      } else {
                        _trafficEta.stop();
                      }
                    }

                    final markers = <SchoolWayMapMarker>[];
                    for (final bid in busIds) {
                      final p = fleetBusMapPosition(
                        gps: gpsByBus[bid],
                        bus: busesById[bid],
                      );
                      if (p == null) continue;
                      markers.add(
                        SchoolWayMapMarker(
                          id: 'bus-$bid',
                          latitude: p.latitude,
                          longitude: p.longitude,
                          width: 72,
                          height: 56,
                          alignment: Alignment.bottomCenter,
                          child: buildFleetBusMarkerWidget(
                            busId: bid,
                            busLabel: busesById[bid]?.busNumber ?? 'BUS',
                          ),
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
                        SchoolWayMapPolyline? selectedGoogleRoutePolyline;
                        var selectedRouteMissingGeometry = false;
                        final selectedStopMarkers = <SchoolWayMapMarker>[];
                        final geofenceCircles = <SchoolWayMapCircle>[];
                        if (selectedBusId != null) {
                          final session = activeByBus[selectedBusId];
                          final selectedBus = busesById[selectedBusId];
                          final routeId =
                              session?.routeId ?? selectedBus?.assignedRouteId;
                          if (routeId != null && routeId.trim().isNotEmpty) {
                            final planned = plannedById[routeId];
                            if (planned != null &&
                                planned.editableStops.length >= 2) {
                              final tripDirection =
                                  session?.tripDirection ??
                                  TripDirection.toSchool;
                              final googleRouteWaypoints = planned
                                  .googleWaypointsForTrip(tripDirection);
                              final routeWaypoints = googleRouteWaypoints;
                              if (googleRouteWaypoints.length >= 2) {
                                selectedGoogleRoutePolyline =
                                    SchoolWayMapPolyline(
                                      id: 'selected-route',
                                      points: googleRouteWaypoints,
                                      strokeWidth: 5,
                                      color: fleetBusAccentColor(
                                        selectedBusId,
                                      ).withValues(alpha: 0.72),
                                    );
                              } else {
                                // Fallback: use editable stops (straight lines between stops)
                                final editableStops = planned
                                    .editableStopsForTrip(tripDirection);
                                if (editableStops.length >= 2) {
                                  selectedGoogleRoutePolyline =
                                      SchoolWayMapPolyline(
                                        id: 'selected-route-fallback',
                                        points: editableStops,
                                        strokeWidth: 4,
                                        color: fleetBusAccentColor(
                                          selectedBusId,
                                        ).withValues(alpha: 0.5),
                                      );
                                }
                                selectedRouteMissingGeometry = true;
                              }

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

                              final trafficSnapshot =
                                  _trafficEta.state.value.snapshot;
                              final trafficEtasByRouteStop = <int, int>{};
                              if (trafficSnapshot != null &&
                                  trafficSnapshot.isOk) {
                                for (final eta in trafficSnapshot.stopEtas) {
                                  trafficEtasByRouteStop[eta.routeStopIndex] =
                                      eta.etaMinutes;
                                }
                              }

                              for (final assignedStop in assignedStops) {
                                final stop = assignedStop.waypoint;

                                geofenceCircles.add(
                                  SchoolWayMapCircle(
                                    id: 'geofence-$selectedBusId-${assignedStop.routeStopIndex}',
                                    latitude: stop.latitude,
                                    longitude: stop.longitude,
                                    radiusMeters: 200,
                                    fillColor: SchoolWayTheme.accent.withValues(
                                      alpha: 0.2,
                                    ),
                                    strokeColor: SchoolWayTheme.accent
                                        .withValues(alpha: 0.5),
                                    strokeWidth: 2,
                                  ),
                                );

                                geofenceCircles.add(
                                  SchoolWayMapCircle(
                                    id: 'pulse-$selectedBusId-${assignedStop.routeStopIndex}',
                                    latitude: stop.latitude,
                                    longitude: stop.longitude,
                                    radiusMeters:
                                        200 + (_pulseController.value * 50),
                                    fillColor: SchoolWayTheme.transparent,
                                    strokeColor: SchoolWayTheme.accent
                                        .withValues(
                                          alpha: _pulseController.value * 0.8,
                                        ),
                                    strokeWidth: 2,
                                  ),
                                );

                                final etaMinutes =
                                    trafficEtasByRouteStop[assignedStop
                                        .routeStopIndex];

                                selectedStopMarkers.add(
                                  SchoolWayMapMarker(
                                    id: 'stop-$selectedBusId-${assignedStop.routeStopIndex}',
                                    latitude: stop.latitude,
                                    longitude: stop.longitude,
                                    width: 60,
                                    height: 44,
                                    alignment: Alignment.bottomCenter,
                                    child: buildStopNumberWidget(
                                      number: assignedStop.serviceStopNumber,
                                      badgeLabel: etaMinutes != null
                                          ? '~$etaMinutes min'
                                          : null,
                                      color: SchoolWayTheme.warning,
                                    ),
                                  ),
                                );
                              }
                              if (routeWaypoints.isNotEmpty) {
                                final finalStop = routeWaypoints.last;
                                selectedStopMarkers.add(
                                  SchoolWayMapMarker(
                                    id: 'final-stop-$selectedBusId',
                                    latitude: finalStop.latitude,
                                    longitude: finalStop.longitude,
                                    width: 24,
                                    height: 24,
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
                              child: AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, _) {
                                  final allCircles = <SchoolWayMapCircle>[
                                    ...geofenceCircles,
                                  ];
                                  for (final stop in selectedStopMarkers) {
                                    allCircles.add(
                                      SchoolWayMapCircle(
                                        id: 'pulse-anim-${stop.id}',
                                        latitude: stop.latitude,
                                        longitude: stop.longitude,
                                        radiusMeters:
                                            200 +
                                            (_pulseController.value * 100),
                                        fillColor: SchoolWayTheme.transparent,
                                        strokeColor: SchoolWayTheme.accent
                                            .withValues(
                                              alpha:
                                                  (1.0 -
                                                      _pulseController.value) *
                                                  0.8,
                                            ),
                                        strokeWidth: 2,
                                      ),
                                    );
                                  }
                                  return ValueListenableBuilder<
                                    TrafficEtaState
                                  >(
                                    valueListenable: _trafficEta.state,
                                    builder: (context, trafficState, _) {
                                      final trafficPolyline =
                                          trafficState.isAvailable &&
                                              trafficState.snapshot != null
                                          ? trafficState.snapshot!
                                                .decodeWaypoints()
                                          : const <RouteWaypoint>[];
                                      return SchoolWayMap(
                                        controller: _mapController,
                                        initialCenter: center,
                                        initialZoom: zoom,
                                        markers: [
                                          ...selectedStopMarkers,
                                          ...markers,
                                          if (_myLocation != null)
                                            buildMyLocationMarker(
                                              id: 'my-location',
                                              position: _myLocation!,
                                            ),
                                        ],
                                        polylines: [
                                          ?selectedGoogleRoutePolyline,
                                          if (trafficPolyline.length >= 2)
                                            SchoolWayMapPolyline(
                                              id: 'parent-traffic-eta',
                                              points: trafficPolyline,
                                              strokeWidth: 5,
                                              color: SchoolWayTheme.violet,
                                            ),
                                        ],
                                        circles: allCircles,
                                        onCameraChanged: _onCameraChanged,
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            Positioned(
                              top: 8,
                              left: 8,
                              child: ValueListenableBuilder<TrafficEtaState>(
                                valueListenable: _trafficEta.state,
                                builder: (context, state, _) => Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TrafficEtaChip(state: state),
                                    if (selectedRouteMissingGeometry)
                                      Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: RouteGeometryMissingBanner(),
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
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerSignal: (_) {},
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
                                                  color:
                                                      SchoolWayTheme.blueGrey,
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
                                                        s.assignedBusId ==
                                                        busId,
                                                  )
                                                  .toList();
                                              final routeIsLive = activeByBus
                                                  .containsKey(busId);

                                              if (bus != null &&
                                                  gps != null &&
                                                  routeIsLive) {
                                                if (busId == _selectedBusId) {
                                                  final snap = _trafficEta
                                                      .state
                                                      .value
                                                      .snapshot;
                                                  if (snap != null &&
                                                      snap.isOk) {
                                                    for (final eta
                                                        in snap.stopEtas) {
                                                      if (minEta == null ||
                                                          eta.etaMinutes <
                                                              minEta) {
                                                        minEta = eta.etaMinutes;
                                                      }
                                                    }
                                                  }
                                                }
                                              }

                                              return _ParentBusSummaryCard(
                                                accentColor:
                                                    fleetBusAccentColor(busId),
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
                                                      () => _selectedBusId =
                                                          busId,
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
                      Flexible(
                        child: Text(
                          'ETA to stop: ~$etaMinutes min',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: SchoolWayTheme.warning,
                          ),
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
