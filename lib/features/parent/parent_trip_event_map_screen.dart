import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/fleet_bus_colors.dart';
import 'package:schoolway/core/widgets/osm_map_attribution.dart';
import 'package:schoolway/core/widgets/osm_map_tile_layer.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/boarding_record_service.dart';
import 'package:schoolway/services/firebase_service.dart';

/// Full-screen map (not the Live Map tab) showing the bus [PlannedRoute] and the
/// NFC scan location for one boarding event.
class ParentTripEventMapScreen extends StatefulWidget {
  const ParentTripEventMapScreen({
    super.key,
    required this.event,
    required this.student,
  });

  final BoardingEvent event;
  final Student student;

  @override
  State<ParentTripEventMapScreen> createState() =>
      _ParentTripEventMapScreenState();
}

class _TripMapData {
  const _TripMapData({this.planned, this.session});

  final PlannedRoute? planned;
  final RouteSession? session;
}

Future<_TripMapData> _loadPlannedAndSession(
  BoardingEvent event,
  Bus? bus,
) async {
  RouteSession? session;
  final sid = event.sessionId?.trim() ?? '';
  if (sid.isNotEmpty) {
    final doc = await FirebaseService.routeSessionsCollection.doc(sid).get();
    if (doc.exists) {
      session = RouteSession.fromFirestore(doc);
    }
  }

  PlannedRoute? planned;
  final fromSession = session?.routeId?.trim() ?? '';
  final fromBus = bus?.assignedRouteId?.trim() ?? '';
  final routeId =
      fromSession.isNotEmpty ? fromSession : fromBus;
  if (routeId.isNotEmpty) {
    planned = await FirebaseService.getPlannedRouteById(routeId);
  }

  return _TripMapData(planned: planned, session: session);
}

List<LatLng> _polylinePoints(PlannedRoute? planned, RouteSession? session) {
  if (planned == null) return [];
  var pts = session != null
      ? planned.waypointsForTrip(session.tripDirection)
      : planned.waypoints;
  if (pts.length < 2) {
    pts = planned.waypoints;
  }
  if (pts.length < 2) return [];
  return pts.map((w) => LatLng(w.latitude, w.longitude)).toList();
}

List<RouteWaypoint> _stopWaypoints(PlannedRoute planned, RouteSession? session) {
  if (session != null) {
    return planned.editableStopsForTrip(session.tripDirection);
  }
  return planned.editableStops;
}

class _ParentTripEventMapScreenState extends State<ParentTripEventMapScreen> {
  final MapController _mapController = MapController();
  String? _loadKey;
  Future<_TripMapData>? _loadFuture;
  String? _lastFitSignature;

  @override
  void dispose() {
    final c = _mapController;
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    super.dispose();
  }

  void _ensureLoadFuture(Bus? bus) {
    final k =
        '${bus?.id ?? ''}|${bus?.assignedRouteId ?? ''}|${widget.event.sessionId ?? ''}';
    if (_loadKey == k) return;
    _loadKey = k;
    _lastFitSignature = null;
    _loadFuture = _loadPlannedAndSession(widget.event, bus);
  }

  void _maybeFitCamera(List<LatLng> points) {
    if (points.isEmpty) return;
    final sig = points
        .map((p) => '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}')
        .join(';');
    if (sig == _lastFitSignature) return;
    _lastFitSignature = sig;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        if (points.length == 1) {
          _mapController.move(points.first, 15);
          return;
        }
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(56),
            maxZoom: 17,
          ),
        );
      } catch (_) {}
    });
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

  LatLng _fallbackCenter() {
    if (widget.event.location.hasValidCoordinates) {
      return LatLng(
        widget.event.location.latitude,
        widget.event.location.longitude,
      );
    }
    return const LatLng(3.1390, 101.6869);
  }

  @override
  Widget build(BuildContext context) {
    final isBoard = BoardingRecordService.isBoardingEventType(
      widget.event.eventType,
    );
    final eventAccent = isBoard
        ? const Color(0xFF4CAF50)
        : const Color(0xFFFF9800);
    final timeStr = DateFormat("MMM d, y 'at' h:mm a").format(widget.event.timestamp);
    final eventLabel = isBoard ? 'Boarded' : 'Dropped off';

    return Scaffold(
      backgroundColor: const Color(0xFFCAF0F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFCAF0F8),
        elevation: 0,
        foregroundColor: const Color(0xFF03045E),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Scan on map',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: Color(0xFF03045E),
              ),
            ),
            Text(
              widget.student.fullName,
              style: const TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: Color(0xFF0077B6),
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<Bus?>(
        stream: FirebaseService.watchBusById(widget.event.busId),
        builder: (context, busSnap) {
          final bus = busSnap.data;
          if (busSnap.connectionState == ConnectionState.waiting &&
              !busSnap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF0077B6)),
            );
          }

          _ensureLoadFuture(bus);

          return FutureBuilder<_TripMapData>(
            future: _loadFuture,
            builder: (context, loadSnap) {
              if (loadSnap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF0077B6)),
                );
              }
              if (loadSnap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load route: ${loadSnap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        color: Color(0xFF03045E),
                      ),
                    ),
                  ),
                );
              }

              final data = loadSnap.data ?? const _TripMapData();
              final planned = data.planned;
              final session = data.session;
              final polylinePts = _polylinePoints(planned, session);
              final accent = fleetBusAccentColor(widget.event.busId);
              final stopWaypoints = planned != null
                  ? _stopWaypoints(planned, session)
                  : <RouteWaypoint>[];

              final markers = <Marker>[];
              for (var i = 0; i < stopWaypoints.length; i++) {
                final s = stopWaypoints[i];
                markers.add(
                  Marker(
                    point: LatLng(s.latitude, s.longitude),
                    width: 28,
                    height: 28,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF00B4D8).withValues(alpha: 0.9),
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
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                );
              }

              if (widget.event.location.hasValidCoordinates) {
                markers.add(
                  Marker(
                    point: LatLng(
                      widget.event.location.latitude,
                      widget.event.location.longitude,
                    ),
                    width: 48,
                    height: 48,
                    alignment: Alignment.topCenter,
                    child: Icon(
                      Icons.place,
                      size: 44,
                      color: eventAccent,
                      shadows: const [
                        Shadow(
                          blurRadius: 4,
                          color: Colors.black26,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final allPts = <LatLng>[...polylinePts];
              if (widget.event.location.hasValidCoordinates) {
                allPts.add(
                  LatLng(
                    widget.event.location.latitude,
                    widget.event.location.longitude,
                  ),
                );
              }
              if (allPts.isEmpty && stopWaypoints.isNotEmpty) {
                for (final s in stopWaypoints) {
                  allPts.add(LatLng(s.latitude, s.longitude));
                }
              }

              _maybeFitCamera(allPts);

              final hasRoute = polylinePts.length >= 2;
              final hasPin = widget.event.location.hasValidCoordinates;
              final emptyMap = !hasRoute && !hasPin && stopWaypoints.isEmpty;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$eventLabel · $timeStr',
                              style: const TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Color(0xFF03045E),
                              ),
                            ),
                            if (bus != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${bus.busNumber} · ${bus.currentRoute ?? 'Route'}',
                                style: const TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 13,
                                  color: Color(0xFF0077B6),
                                ),
                              ),
                            ],
                            if (planned != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Planned route: ${planned.name}',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 12,
                                  color: Colors.blueGrey.shade700,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _LegendDot(color: accent, label: 'Planned path'),
                                const SizedBox(width: 16),
                                _LegendDot(
                                  color: const Color(0xFF00B4D8),
                                  label: 'Stops',
                                ),
                                const SizedBox(width: 16),
                                _LegendDot(
                                  color: eventAccent,
                                  label: 'Scan',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: emptyMap
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No planned route is assigned to this bus, and this scan has no GPS position. Nothing to show on the map yet.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 14,
                                  color: Colors.blueGrey.shade700,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned.fill(
                                child: FlutterMap(
                                  mapController: _mapController,
                                  options: MapOptions(
                                    initialCenter: allPts.isNotEmpty
                                        ? allPts.first
                                        : _fallbackCenter(),
                                    initialZoom: allPts.length >= 2 ? 12 : 15,
                                    interactionOptions: const InteractionOptions(
                                      flags: InteractiveFlag.all,
                                    ),
                                  ),
                                  children: [
                                    const OsmMapTileLayer(),
                                    if (hasRoute)
                                      PolylineLayer(
                                        polylines: [
                                          Polyline(
                                            points: polylinePts,
                                            strokeWidth: 5,
                                            color: accent.withValues(alpha: 0.78),
                                          ),
                                        ],
                                      ),
                                    if (markers.isNotEmpty)
                                      MarkerLayer(markers: markers),
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
                                right: 12,
                                child: Column(
                                  children: [
                                    _MapBtn(
                                      icon: Icons.add,
                                      tooltip: 'Zoom in',
                                      onPressed: _zoomIn,
                                    ),
                                    const SizedBox(height: 8),
                                    _MapBtn(
                                      icon: Icons.remove,
                                      tooltip: 'Zoom out',
                                      onPressed: _zoomOut,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                  if (!hasPin && (hasRoute || planned != null))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Text(
                        'GPS was not recorded for this scan. The line shows the planned route.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.blueGrey.shade600,
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 11,
            color: Colors.blueGrey.shade800,
          ),
        ),
      ],
    );
  }
}

class _MapBtn extends StatelessWidget {
  const _MapBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: IconButton(
        icon: Icon(icon, color: const Color(0xFF0077B6)),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }
}
