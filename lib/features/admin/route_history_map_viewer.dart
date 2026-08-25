import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/error_reporter.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/core/map/map_markers.dart';
import 'package:schoolway/core/map/schoolway_map.dart';
import 'package:schoolway/core/map/schoolway_map_controller.dart';

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
  final SchoolWayMapController _mapController = SchoolWayMapController();
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
      _mapController.move(
        center: LatLng(gps.latitude, gps.longitude),
        zoom: 15,
      );
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routePolylinePoints = widget.route != null
        ? widget.route!.googleWaypointsForTrip(widget.session.tripDirection)
        : const <RouteWaypoint>[];

    final stopMarkers = <SchoolWayMapMarker>[];
    if (widget.route != null) {
      final routeStops = widget.route!.editableStops;
      final serviceIndices = widget.session.serviceStopRouteIndices;
      for (var i = 0; i < serviceIndices.length; i++) {
        final routeStopIndex = serviceIndices[i];
        if (routeStopIndex < 0 || routeStopIndex >= routeStops.length) continue;
        final stop = routeStops[routeStopIndex];
        stopMarkers.add(
          SchoolWayMapMarker(
            id: 'history-stop-$routeStopIndex',
            latitude: stop.latitude,
            longitude: stop.longitude,
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
              ? LatLng(
                  routePolylinePoints.first.latitude,
                  routePolylinePoints.first.longitude,
                )
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
                  child: SchoolWayMap(
                    controller: _mapController,
                    initialCenter: center,
                    initialZoom: 14,
                    markers: [
                      ...stopMarkers,
                      if (currentGps != null)
                        SchoolWayMapMarker(
                          id: 'history-bus',
                          latitude: currentGps.latitude,
                          longitude: currentGps.longitude,
                          width: 90,
                          height: 72,
                          alignment: Alignment.bottomCenter,
                          child: buildFleetBusMarkerWidget(
                            busId: widget.session.busId,
                            busLabel: widget.bus?.busNumber ?? 'BUS',
                          ),
                        ),
                    ],
                    polylines: [
                      if (routePolylinePoints.length >= 2)
                        SchoolWayMapPolyline(
                          id: 'history-route',
                          points: routePolylinePoints,
                          strokeWidth: 4,
                          color: SchoolWayTheme.primary.withValues(alpha: 0.5),
                        ),
                      if (_breadcrumbs.length >= 2)
                        SchoolWayMapPolyline(
                          id: 'history-breadcrumbs',
                          points: _breadcrumbs
                              .sublist(0, _currentIndex + 1)
                              .map(
                                (g) => RouteWaypoint(
                                  latitude: g.latitude,
                                  longitude: g.longitude,
                                ),
                              )
                              .toList(),
                          strokeWidth: 5,
                          color: SchoolWayTheme.warning,
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
