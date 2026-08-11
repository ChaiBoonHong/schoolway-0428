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
  static final RegExp _stopIndexPattern = RegExp(r'^Stop\s+(\d+)\b');

  int? _stopIndexFromLabel(String? label) {
    if (label == null) return null;
    final m = _stopIndexPattern.firstMatch(label.trim());
    if (m == null) return null;
    final parsed = int.tryParse(m.group(1) ?? '');
    if (parsed == null || parsed <= 0) return null;
    return parsed - 1;
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
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
    } catch (_) {}
  }

  static LatLng _mapCenterFromPoints(List<LatLng> pts) {
    if (pts.isEmpty) return const LatLng(3.1390, 101.6869);
    final lat = pts.map((e) => e.latitude).reduce((a, b) => a + b) / pts.length;
    final lng =
        pts.map((e) => e.longitude).reduce((a, b) => a + b) / pts.length;
    return LatLng(lat, lng);
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

  Widget _buildMapControlButton(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool loading = false,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF0077B6),
                ),
              ),
            )
          : IconButton(
              icon: Icon(icon, color: const Color(0xFF0077B6)),
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
          const SnackBar(
            content: Text(
              'Location permission is required to show your position on the map.',
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: Color(0xFFFF9800),
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
      return const Center(child: Text('Please sign in'));
    }

    return StreamBuilder<List<Student>>(
      stream: FirebaseService.getStudentsByParentAuthUid(_currentUserId),
      builder: (context, studentSnapshot) {
        if (studentSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF0077B6)),
          );
        }

        if (studentSnapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${studentSnapshot.error}',
              style: const TextStyle(fontFamily: 'Lexend'),
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
                  color: const Color(0xFF00B4D8),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No students found',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Contact kindergarten admin to add your child',
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
          return const Center(
            child: Text(
              'No bus assigned yet',
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
                              selectedRoutePolyline = Polyline(
                                points: planned.waypoints
                                    .map((w) => LatLng(w.latitude, w.longitude))
                                    .toList(),
                                strokeWidth: 5,
                                color: fleetBusAccentColor(
                                  selectedBusId,
                                ).withValues(alpha: 0.72),
                              );

                              final routeStops = planned.editableStops;
                              final addedStopIdx = <int>{};
                              final studentsOnSelectedBus = students.where(
                                (s) => s.assignedBusId == selectedBusId,
                              );

                              final gps = gpsByBus[selectedBusId];

                              int nextStopIdx = 0;
                              if (gps != null && routeStops.isNotEmpty) {
                                nextStopIdx =
                                    EtaGeofenceService.getNextStopIndex(
                                      currentPos: LatLng(
                                        gps.latitude,
                                        gps.longitude,
                                      ),
                                      stops: routeStops,
                                    );
                              }

                              for (final student in studentsOnSelectedBus) {
                                final idx = _stopIndexFromLabel(
                                  student.pickupStop,
                                );
                                if (idx == null ||
                                    idx < 0 ||
                                    idx >= routeStops.length ||
                                    !addedStopIdx.add(idx)) {
                                  continue;
                                }
                                final stop = routeStops[idx];
                                final stopPos = LatLng(
                                  stop.latitude,
                                  stop.longitude,
                                );

                                geofenceCircles.add(
                                  CircleMarker(
                                    point: stopPos,
                                    color: const Color(
                                      0xFF00B4D8,
                                    ).withValues(alpha: 0.2),
                                    borderStrokeWidth: 2,
                                    borderColor: const Color(
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
                                    color: Colors.transparent,
                                    borderStrokeWidth: 2,
                                    borderColor: const Color(0xFF00B4D8)
                                        .withValues(
                                          alpha: _pulseController.value * 0.8,
                                        ),
                                    useRadiusInMeter: true,
                                    radius: 200 + (_pulseController.value * 50),
                                  ),
                                );

                                int? etaMinutes;
                                if (gps != null && idx >= nextStopIdx) {
                                  final pathStops = routeStops.sublist(
                                    nextStopIdx,
                                    idx + 1,
                                  );
                                  etaMinutes =
                                      EtaGeofenceService.calculateEtaMinutes(
                                        currentPos: LatLng(
                                          gps.latitude,
                                          gps.longitude,
                                        ),
                                        remainingStops: pathStops,
                                        speedKmh: gps.speed,
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
                                              color: Colors.white.withValues(
                                                alpha: 0.9,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: const Color(0xFFFF9800),
                                                width: 1,
                                              ),
                                            ),
                                            child: Text(
                                              '~$etaMinutes min',
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
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFF9800),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${idx + 1}',
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
                              if (routeStops.isNotEmpty) {
                                final finalStop = routeStops.last;
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
                                        color: const Color(0xFF4CAF50),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.flag,
                                        size: 18,
                                        color: Colors.white,
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
                                  const OsmMapTileLayer(),
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
                                              color: Colors.transparent,
                                              borderStrokeWidth: 2,
                                              borderColor:
                                                  const Color(
                                                    0xFF00B4D8,
                                                  ).withValues(
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
                                              color: const Color(0xFF2196F3),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
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
                                  const SizedBox(height: 8),
                                  _buildMapControlButton(
                                    Icons.add,
                                    'Zoom in',
                                    _zoomIn,
                                  ),
                                  const SizedBox(height: 8),
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
                                constraints: const BoxConstraints(
                                  maxHeight: 240,
                                ),
                                child: Material(
                                  color: Colors.transparent,
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
                                                color: Colors.blueGrey.shade700,
                                              ),
                                            ),
                                          ),
                                        for (
                                          var i = 0;
                                          i < busIds.length;
                                          i++
                                        ) ...[
                                          if (i > 0) const SizedBox(height: 10),
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
                                              final currentRouteId =
                                                  bus.currentRoute;
                                              if (currentRouteId != null) {
                                                final routeStops =
                                                    plannedById[currentRouteId]
                                                        ?.editableStops ??
                                                    [];
                                                if (routeStops.isNotEmpty) {
                                                  final nextStopIdx =
                                                      EtaGeofenceService.getNextStopIndex(
                                                        currentPos: LatLng(
                                                          gps.latitude,
                                                          gps.longitude,
                                                        ),
                                                        stops: routeStops,
                                                      );
                                                  for (final student
                                                      in studentsOnBus) {
                                                    final stopIdx =
                                                        _stopIndexFromLabel(
                                                          student.pickupStop,
                                                        );
                                                    if (stopIdx != null &&
                                                        stopIdx >=
                                                            nextStopIdx &&
                                                        stopIdx <
                                                            routeStops.length) {
                                                      final eta =
                                                          EtaGeofenceService.calculateEtaMinutes(
                                                            currentPos: LatLng(
                                                              gps.latitude,
                                                              gps.longitude,
                                                            ),
                                                            remainingStops:
                                                                routeStops
                                                                    .sublist(
                                                                      nextStopIdx,
                                                                      stopIdx +
                                                                          1,
                                                                    ),
                                                            speedKmh: gps.speed,
                                                          );
                                                      if (minEta == null ||
                                                          eta < minEta) {
                                                        minEta = eta;
                                                      }
                                                    }
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
      color: Colors.transparent,
      child: InkWell(
        onTap: onShowOnMap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
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
                      color: routeIsLive ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.directions_bus, color: accentColor, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      busLabel,
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF03045E),
                      ),
                    ),
                  ),
                  if (onShowOnMap != null)
                    const Icon(
                      Icons.open_in_full,
                      size: 18,
                      color: Color(0xFF0077B6),
                    ),
                ],
              ),
              if (childNames.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  childNames,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13,
                    color: Colors.blueGrey.shade800,
                  ),
                ),
              ],
              if (simulated) ...[
                const SizedBox(height: 6),
                const Chip(
                  avatar: Icon(Icons.science_outlined, size: 16),
                  label: Text(
                    'Simulated position',
                    style: TextStyle(fontFamily: 'Lexend'),
                  ),
                ),
              ],
              if (fleetBusHasMapPosition(gps: gps, bus: bus)) ...[
                const SizedBox(height: 6),
                Text(
                  routeIsLive
                      ? 'Tap to show this bus on the map'
                      : 'Last known position (route not active)',
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12,
                    color: Color(0xFF00B4D8),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                routeIsLive
                    ? 'Live · Last update: ${fleetBusLastSeenLabel(gps: gps, bus: bus)}'
                    : (fleetBusHasMapPosition(gps: gps, bus: bus)
                          ? 'Last seen: ${fleetBusLastSeenLabel(gps: gps, bus: bus)}'
                          : 'No tracking data'),
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 14,
                  color: Color(0xFF0077B6),
                ),
              ),
              if (bus?.currentRoute != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Route: ${bus!.currentRoute}',
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14,
                    color: Color(0xFF0077B6),
                  ),
                ),
              ],
              if (etaMinutes != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFF9800)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.timer,
                        size: 16,
                        color: Color(0xFFFF9800),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'ETA to stop: ~$etaMinutes min',
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF9800),
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
