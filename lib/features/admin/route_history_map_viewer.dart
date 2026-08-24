import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/error_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/core/widgets/osm_map_tile_layer.dart';
import 'package:schoolway/core/widgets/osm_map_attribution.dart';
import 'package:schoolway/core/widgets/fleet_bus_marker.dart';

class RouteHistoryMapViewer extends StatefulWidget {
  final RouteSession session;
  final Bus? bus;
  final PlannedRoute? route;

  const RouteHistoryMapViewer({
    super.key,
    required this.session,
    this.bus,
    this.route,
  });

  @override
  State<RouteHistoryMapViewer> createState() => _RouteHistoryMapViewerState();
}

class _RouteHistoryMapViewerState extends State<RouteHistoryMapViewer> {
  final MapController _mapController = MapController();
  List<GpsTracking> _breadcrumbs = [];
  bool _loading = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadBreadcrumbs();
  }

  Future<void> _loadBreadcrumbs() async {
    try {
      final logs = await FirebaseService.getRouteSessionBreadcrumbs(
        widget.session.id,
      );
      if (mounted) {
        setState(() {
          _breadcrumbs = logs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorReporter.userMessage(
                context,
                e,
                StackTrace.current,
                category: 'routes',
                message: 'Route history failed to load.',
              ),
            ),
          ),
        );
      }
    }
  }

  void _onSliderChanged(double value) {
    setState(() {
      _currentIndex = value.toInt();
    });
    if (_breadcrumbs.isNotEmpty && _currentIndex < _breadcrumbs.length) {
      final gps = _breadcrumbs[_currentIndex];
      _mapController.move(LatLng(gps.latitude, gps.longitude), 15);
    }
  }

  @override
  Widget build(BuildContext context) {
    final routePolylinePoints = widget.route != null
        ? widget.route!
              .waypointsForTrip(widget.session.tripDirection)
              .map((w) => LatLng(w.latitude, w.longitude))
              .toList()
        : const <LatLng>[];

    final stopMarkers = <Marker>[];
    if (widget.route != null) {
      final stops = widget.route!.editableStopsForTrip(
        widget.session.tripDirection,
      );
      for (var i = 0; i < stops.length; i++) {
        final stop = stops[i];
        stopMarkers.add(
          Marker(
            point: LatLng(stop.latitude, stop.longitude),
            width: 30,
            height: 30,
            child: Container(
              decoration: BoxDecoration(
                color: SchoolWayTheme.accent,
                shape: BoxShape.circle,
                border: Border.all(color: SchoolWayTheme.surface, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  color: SchoolWayTheme.surface,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        );
      }
    }

    final hasData = _breadcrumbs.isNotEmpty;
    final currentGps = hasData ? _breadcrumbs[_currentIndex] : null;

    final center = hasData
        ? LatLng(_breadcrumbs.first.latitude, _breadcrumbs.first.longitude)
        : (routePolylinePoints.isNotEmpty
              ? routePolylinePoints.first
              : LatLng(3.1390, 101.6869));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: SchoolWayTheme.background,
        elevation: 0,
        foregroundColor: SchoolWayTheme.navy,
        title: Text(
          widget.bus?.busNumber ?? 'Unknown Bus',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            color: SchoolWayTheme.navy,
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: center,
                          initialZoom: 14,
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
                                  ).withValues(alpha: 0.5),
                                ),
                              ],
                            ),
                          // Breadcrumbs polyline
                          if (_breadcrumbs.length >= 2)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _breadcrumbs
                                      .sublist(0, _currentIndex + 1)
                                      .map(
                                        (g) => LatLng(g.latitude, g.longitude),
                                      )
                                      .toList(),
                                  strokeWidth: 5,
                                  color: SchoolWayTheme.warning,
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              ...stopMarkers,
                              if (currentGps != null)
                                buildFleetBusMarker(
                                  point: LatLng(
                                    currentGps.latitude,
                                    currentGps.longitude,
                                  ),
                                  busId: widget.session.busId,
                                  busLabel: widget.bus?.busNumber ?? 'BUS',
                                ),
                            ],
                          ),
                        ],
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
                    ],
                  ),
                ),
                Container(
                  color: SchoolWayTheme.surface,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (!hasData)
                        Text(
                          AppLocalizations.of(
                            context,
                          ).noGpsDataAvailableForThisSession,
                          style: TextStyle(fontFamily: 'Lexend'),
                        )
                      else ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              DateFormat(
                                'hh:mm:ss a',
                              ).format(currentGps!.timestamp),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.bold,
                                color: SchoolWayTheme.navy,
                              ),
                            ),
                            Text(
                              '${currentGps.speed.toStringAsFixed(1)} km/h',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.bold,
                                color: SchoolWayTheme.primary,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _currentIndex.toDouble(),
                          min: 0,
                          max: (_breadcrumbs.length - 1).toDouble(),
                          onChanged: _onSliderChanged,
                          activeColor: SchoolWayTheme.accent,
                          inactiveColor: SchoolWayTheme.muted,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
