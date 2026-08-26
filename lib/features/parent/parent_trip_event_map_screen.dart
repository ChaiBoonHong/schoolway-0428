import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/fleet_bus_colors.dart';
import 'package:schoolway/core/map/schoolway_map.dart';
import 'package:schoolway/core/map/schoolway_map_controller.dart';
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
  const _TripMapData({this.planned, this.session, this.breadcrumbs = const []});

  final PlannedRoute? planned;
  final RouteSession? session;
  final List<RouteBreadcrumb> breadcrumbs;
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
  final routeId = fromSession.isNotEmpty ? fromSession : fromBus;
  if (routeId.isNotEmpty) {
    planned = await FirebaseService.getPlannedRouteById(routeId);
  }

  List<RouteBreadcrumb> breadcrumbs = [];
  if (sid.isNotEmpty) {
    final snap = await FirebaseService.routeSessionsCollection
        .doc(sid)
        .collection('breadcrumbs')
        .orderBy('timestamp', descending: false)
        .get();
    breadcrumbs = snap.docs
        .map((d) => RouteBreadcrumb.fromFirestore(d))
        .toList();
  }

  return _TripMapData(
    planned: planned,
    session: session,
    breadcrumbs: breadcrumbs,
  );
}

List<RouteWaypoint> _googlePolylinePoints(
  PlannedRoute? planned,
  RouteSession? session,
) {
  if (planned == null) return [];
  final pts = session != null
      ? planned.googleWaypointsForTrip(session.tripDirection)
      : planned.googleWaypointsForTrip(TripDirection.toSchool);
  return pts.length >= 2 ? pts : const [];
}

List<RouteWaypoint> _stopWaypoints(
  PlannedRoute planned,
  RouteSession? session,
) {
  if (session != null && session.serviceStopRouteIndices.isNotEmpty) {
    final routeStops = planned.editableStops;
    return session.serviceStopRouteIndices
        .where((index) => index >= 0 && index < routeStops.length)
        .map((index) => routeStops[index])
        .toList();
  }
  return const [];
}

class _ParentTripEventMapScreenState extends State<ParentTripEventMapScreen> {
  final SchoolWayMapController _mapController = SchoolWayMapController();
  double _zoom = 14;
  String? _loadKey;
  Future<_TripMapData>? _loadFuture;
  String? _lastFitSignature;

  @override
  void dispose() {
    _mapController.dispose();
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
        .map(
          (p) =>
              '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}',
        )
        .join(';');
    if (sig == _lastFitSignature) return;
    _lastFitSignature = sig;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (points.length == 1) {
        _mapController.move(center: points.first, zoom: 15);
        return;
      }
      var south = points.first.latitude;
      var north = points.first.latitude;
      var west = points.first.longitude;
      var east = points.first.longitude;
      for (final p in points) {
        south = p.latitude < south ? p.latitude : south;
        north = p.latitude > north ? p.latitude : north;
        west = p.longitude < west ? p.longitude : west;
        east = p.longitude > east ? p.longitude : east;
      }
      _mapController.fitBounds(
        southLatitude: south,
        westLongitude: west,
        northLatitude: north,
        eastLongitude: east,
        padding: 56,
      );
    });
  }

  void _zoomIn() {
    final center = _mapController.lastRequestedCenter ?? _fallbackCenter();
    _mapController.move(center: center, zoom: _zoom + 1);
  }

  void _zoomOut() {
    final center = _mapController.lastRequestedCenter ?? _fallbackCenter();
    _mapController.move(center: center, zoom: _zoom - 1);
  }

  LatLng _fallbackCenter() {
    if (widget.event.location.hasValidCoordinates) {
      return LatLng(
        widget.event.location.latitude,
        widget.event.location.longitude,
      );
    }
    return LatLng(3.1390, 101.6869);
  }

  @override
  Widget build(BuildContext context) {
    final isBoard = BoardingRecordService.isBoardingEventType(
      widget.event.eventType,
    );
    final eventAccent = isBoard
        ? SchoolWayTheme.successBright
        : SchoolWayTheme.warning;
    final timeStr = DateFormat(
      "MMM d, y 'at' h:mm a",
    ).format(widget.event.timestamp);
    final eventLabel = isBoard ? 'Boarded' : 'Dropped off';

    return Scaffold(
      backgroundColor: SchoolWayTheme.background,
      appBar: AppBar(
        backgroundColor: SchoolWayTheme.background,
        elevation: 0,
        foregroundColor: SchoolWayTheme.navy,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context).scanOnMap,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: SchoolWayTheme.navy,
              ),
            ),
            Text(
              widget.student.fullName,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: SchoolWayTheme.primary,
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
            return Center(
              child: CircularProgressIndicator(color: SchoolWayTheme.primary),
            );
          }

          _ensureLoadFuture(bus);

          return FutureBuilder<_TripMapData>(
            future: _loadFuture,
            builder: (context, loadSnap) {
              if (loadSnap.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(
                    color: SchoolWayTheme.primary,
                  ),
                );
              }
              if (loadSnap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load route: ${loadSnap.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: SchoolWayTheme.navy,
                      ),
                    ),
                  ),
                );
              }

              final data = loadSnap.data ?? const _TripMapData();
              final planned = data.planned;
              final session = data.session;
              final polylinePts = _googlePolylinePoints(planned, session);
              final accent = fleetBusAccentColor(widget.event.busId);
              final stopWaypoints = planned != null
                  ? _stopWaypoints(planned, session)
                  : <RouteWaypoint>[];
              final breadcrumbs = data.breadcrumbs;
              final breadcrumbPoints = breadcrumbs
                  .map(
                    (b) => RouteWaypoint(
                      latitude: b.latitude,
                      longitude: b.longitude,
                    ),
                  )
                  .where((p) => p.latitude != 0.0 && p.longitude != 0.0)
                  .toList();

              final markers = <SchoolWayMapMarker>[];
              for (var i = 0; i < stopWaypoints.length; i++) {
                final s = stopWaypoints[i];
                markers.add(
                  SchoolWayMapMarker(
                    id: 'trip-stop-$i',
                    latitude: s.latitude,
                    longitude: s.longitude,
                    width: 28,
                    height: 28,
                    child: Container(
                      decoration: BoxDecoration(
                        color: SchoolWayTheme.accent.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: SchoolWayTheme.surface,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          color: SchoolWayTheme.surface,
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
                  SchoolWayMapMarker(
                    id: 'trip-event-location',
                    latitude: widget.event.location.latitude,
                    longitude: widget.event.location.longitude,
                    width: 32,
                    height: 32,
                    alignment: Alignment.bottomCenter,
                    child: Icon(
                      Icons.place,
                      size: 28,
                      color: eventAccent,
                      shadows: [
                        Shadow(
                          blurRadius: 4,
                          color: SchoolWayTheme.text26,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final allPts = <LatLng>[
                for (final w in polylinePts) LatLng(w.latitude, w.longitude),
              ];
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
                      color: SchoolWayTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$eventLabel · $timeStr',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: SchoolWayTheme.navy,
                              ),
                            ),
                            if (bus != null) ...[
                              SizedBox(height: 4),
                              Text(
                                '${bus.busNumber} · ${bus.currentRoute ?? 'Route'}',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 13,
                                  color: SchoolWayTheme.primary,
                                ),
                              ),
                            ],
                            if (planned != null) ...[
                              SizedBox(height: 2),
                              Text(
                                'Planned route: ${planned.name}',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 12,
                                  color: SchoolWayTheme.blueGrey,
                                ),
                              ),
                            ],
                            SizedBox(height: 8),
                            Row(
                              children: [
                                _LegendDot(
                                  color: accent,
                                  label: AppLocalizations.of(
                                    context,
                                  ).plannedPath,
                                ),
                                SizedBox(width: 16),
                                _LegendDot(
                                  color: SchoolWayTheme.accent,
                                  label: AppLocalizations.of(context).stops,
                                ),
                                SizedBox(width: 16),
                                _LegendDot(
                                  color: eventAccent,
                                  label: AppLocalizations.of(context).scan,
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
                                AppLocalizations.of(
                                  context,
                                ).noPlannedRouteIsAssignedToThis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 14,
                                  color: SchoolWayTheme.blueGrey,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned.fill(
                                child: SchoolWayMap(
                                  controller: _mapController,
                                  initialCenter: allPts.isNotEmpty
                                      ? allPts.first
                                      : _fallbackCenter(),
                                  initialZoom: allPts.length >= 2 ? 12 : 15,
                                  markers: markers,
                                  polylines: [
                                    if (polylinePts.isNotEmpty)
                                      SchoolWayMapPolyline(
                                        id: 'trip-route',
                                        points: polylinePts,
                                        strokeWidth: 4,
                                        color: accent.withValues(alpha: 0.5),
                                      ),
                                    if (breadcrumbPoints.isNotEmpty)
                                      SchoolWayMapPolyline(
                                        id: 'trip-breadcrumbs',
                                        points: breadcrumbPoints,
                                        strokeWidth: 4,
                                        color: SchoolWayTheme.pink,
                                      ),
                                  ],
                                  onCameraChanged: (lat, lng, zoom) {
                                    _zoom = zoom;
                                  },
                                ),
                              ),
                              Positioned(
                                top: 40,
                                right: 12,
                                child: Column(
                                  children: [
                                    _MapBtn(
                                      icon: Icons.add,
                                      tooltip: AppLocalizations.of(
                                        context,
                                      ).zoomIn,
                                      onPressed: _zoomIn,
                                    ),
                                    SizedBox(height: 8),
                                    _MapBtn(
                                      icon: Icons.remove,
                                      tooltip: AppLocalizations.of(
                                        context,
                                      ).zoomOut,
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
                        AppLocalizations.of(
                          context,
                        ).gpsWasNotRecordedForThisScan,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: SchoolWayTheme.blueGrey,
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
            border: Border.all(color: SchoolWayTheme.surface, width: 1),
            boxShadow: [
              BoxShadow(
                color: SchoolWayTheme.text.withValues(alpha: 0.12),
                blurRadius: 2,
              ),
            ],
          ),
        ),
        SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 11,
            color: SchoolWayTheme.blueGrey,
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
      color: SchoolWayTheme.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: IconButton(
        icon: Icon(icon, color: SchoolWayTheme.primary),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }
}
