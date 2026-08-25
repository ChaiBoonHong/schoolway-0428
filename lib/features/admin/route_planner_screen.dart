import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/map/map_markers.dart';
import 'package:schoolway/core/map/schoolway_map.dart';
import 'package:schoolway/core/map/schoolway_map_controller.dart';
import 'package:schoolway/core/widgets/osm_map_attribution.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/services/location_service.dart';
import 'package:schoolway/services/routes_api_service.dart';

/// Route planner: tap the map to drop ordered pins; the line follows Google
/// DRIVE geometry computed by the backend `computePlannedRoute` callable,
/// refreshed as stops change.
class RoutePlannerScreen extends StatefulWidget {
  const RoutePlannerScreen({super.key});

  static const routeName = '/admin/route-planner';

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  static const LatLng _initialCenter = LatLng(3.1390, 101.6869);
  static const Duration _geometryDebounce = Duration(milliseconds: 250);

  final SchoolWayMapController _mapController = SchoolWayMapController();
  final _nameController = TextEditingController();
  final _durationController = TextEditingController(text: '45');

  Timer? _geometryDebounceTimer;
  int _geometryGeneration = 0;

  bool _inEditor = false;

  String? _editingId;
  DateTime _routeCreatedAt = DateTime.now();
  final List<RouteWaypoint> _waypoints = [];

  /// Full road geometry from Google for current [_waypoints] (debounced).
  GoogleRouteGeometry? _geometry;

  /// Waypoint list that [_geometry] was computed for (for save + stale checks).
  List<RouteWaypoint>? _geometryStops;

  bool _geometryLoading = false;
  bool _saving = false;
  bool _locatingSelf = false;
  LatLng? _myLocation;
  double _zoom = 12;

  @override
  void dispose() {
    _geometryDebounceTimer?.cancel();
    _nameController.dispose();
    _durationController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _newRoute() {
    _geometryDebounceTimer?.cancel();
    setState(() {
      _inEditor = true;
      _editingId = null;
      _nameController.clear();
      _durationController.text = '45';
      _routeCreatedAt = DateTime.now();
      _waypoints.clear();
      _geometry = null;
      _geometryStops = null;
      _geometryLoading = false;
    });
  }

  void _openEditorForNewRoute() {
    _newRoute();
    setState(() => _inEditor = true);
  }

  void _openEditorForRoute(PlannedRoute r) {
    _loadRoute(r);
    setState(() => _inEditor = true);
  }

  void _closeEditor() {
    setState(() => _inEditor = false);
  }

  void _loadRoute(PlannedRoute r) {
    final stops = r.editableStops;
    _geometryDebounceTimer?.cancel();
    setState(() {
      _inEditor = true;
      _editingId = r.id;
      _nameController.text = r.name;
      _durationController.text = r.expectedDurationMinutes.toString();
      _routeCreatedAt = r.createdAt;
      _waypoints.clear();
      _waypoints.addAll(stops);
      final geometry = r.googleGeometry;
      if (stops.length >= 2 && geometry != null) {
        _geometry = geometry;
        _geometryStops = List<RouteWaypoint>.from(stops);
      } else {
        _geometry = null;
        _geometryStops = null;
      }
      _geometryLoading = stops.length >= 2;
    });
    if (stops.isNotEmpty) {
      final first = stops.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(
          center: LatLng(first.latitude, first.longitude),
          zoom: 13,
        );
      });
    }
    if (stops.length >= 2) {
      _scheduleGeometryRefresh();
    }
  }

  bool _sameStops(List<RouteWaypoint> a, List<RouteWaypoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude) {
        return false;
      }
    }
    return true;
  }

  void _scheduleGeometryRefresh() {
    _geometryDebounceTimer?.cancel();
    _geometryDebounceTimer = Timer(_geometryDebounce, _runGeometryRefresh);
  }

  Future<void> _runGeometryRefresh() async {
    final gen = ++_geometryGeneration;
    final stopsSnapshot = List<RouteWaypoint>.from(_waypoints);

    if (stopsSnapshot.length < 2) {
      if (!mounted || gen != _geometryGeneration) return;
      setState(() {
        _geometry = null;
        _geometryStops = null;
        _geometryLoading = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _geometryLoading = true);
    }

    try {
      final result = await RoutesApiService.computePlannedRoute(
        stops: stopsSnapshot,
      );
      if (!mounted || gen != _geometryGeneration) return;
      if (!_sameStops(stopsSnapshot, _waypoints)) return;
      final geometry = GoogleRouteGeometry(
        encodedPolyline: result.encodedPolyline,
        distanceMeters: result.distanceMeters,
        durationSeconds: result.durationSeconds,
        stopHash: result.stopHash,
        generatedAt: result.generatedAt,
        expiresAt: result.expiresAt,
      );
      setState(() {
        _geometry = geometry;
        _geometryStops = List<RouteWaypoint>.from(stopsSnapshot);
        _geometryLoading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.warning(
        'routes',
        'Driving route refresh failed; a straight route was used.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || gen != _geometryGeneration) return;
      if (!_sameStops(stopsSnapshot, _waypoints)) return;
      setState(() {
        _geometry = null;
        _geometryStops = null;
        _geometryLoading = false;
      });
    }
  }

  void _addWaypoint(LatLng latLng) {
    setState(() {
      _waypoints.add(
        RouteWaypoint(latitude: latLng.latitude, longitude: latLng.longitude),
      );
    });
    _scheduleGeometryRefresh();
  }

  void _undoLastWaypoint() {
    if (_waypoints.isEmpty) return;
    setState(() => _waypoints.removeLast());
    _scheduleGeometryRefresh();
  }

  void _clearWaypoints() {
    if (_waypoints.isEmpty) return;
    _geometryDebounceTimer?.cancel();
    setState(() {
      _waypoints.clear();
      _geometry = null;
      _geometryStops = null;
      _geometryLoading = false;
    });
  }

  Future<GoogleRouteGeometry?> _computeGeometryForSave(
    List<RouteWaypoint> tapped,
  ) async {
    if (tapped.length < 2) return null;
    if (_geometry != null &&
        _geometryStops != null &&
        _sameStops(tapped, _geometryStops!)) {
      return _geometry;
    }
    try {
      final result = await RoutesApiService.computePlannedRoute(stops: tapped);
      return GoogleRouteGeometry(
        encodedPolyline: result.encodedPolyline,
        distanceMeters: result.distanceMeters,
        durationSeconds: result.durationSeconds,
        stopHash: result.stopHash,
        generatedAt: result.generatedAt,
        expiresAt: result.expiresAt,
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'routes',
        'Waypoint generation failed; selected map points were retained.',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).enterARouteName,
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: SchoolWayTheme.warning,
        ),
      );
      return;
    }
    if (_waypoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).tapTheMapToAddAtLeast,
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: SchoolWayTheme.warning,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final wasNew = _editingId == null;
      final tapped = List<RouteWaypoint>.from(_waypoints);

      final geometry = await _computeGeometryForSave(tapped);
      final geometryWaypoints =
          geometry?.decodeWaypoints() ?? const <RouteWaypoint>[];
      final waypointsToSave = geometryWaypoints.length >= 2
          ? geometryWaypoints
          : tapped;

      final duration = int.tryParse(_durationController.text.trim()) ?? 45;

      final route = PlannedRoute(
        id: _editingId ?? '',
        name: name,
        stops: tapped,
        waypoints: waypointsToSave,
        createdAt: _routeCreatedAt,
        updatedAt: wasNew ? null : DateTime.now(),
        expectedDurationMinutes: duration,
        googleGeometry: geometry,
      );
      final id = await FirebaseService.savePlannedRoute(route);
      if (!mounted) return;
      setState(() {
        _editingId = id;
        if (geometry != null) {
          _geometry = geometry;
          _geometryStops = List<RouteWaypoint>.from(tapped);
        }
      });
      if (tapped.length >= 2) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scheduleGeometryRefresh();
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasNew ? 'Route created' : 'Route saved',
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: SchoolWayTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Save failed: $e',
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: SchoolWayTheme.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete(PlannedRoute r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          AppLocalizations.of(context).deleteRoute,
          style: TextStyle(fontFamily: 'Lexend'),
        ),
        content: Text(r.name, style: TextStyle(fontFamily: 'Lexend')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppLocalizations.of(context).delete,
              style: TextStyle(color: SchoolWayTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseService.deletePlannedRoute(r.id);
      if (!mounted) return;
      if (_editingId == r.id) {
        _newRoute();
        setState(() => _inEditor = false);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).routeDeleted,
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: SchoolWayTheme.warning,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Delete failed: $e',
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: SchoolWayTheme.danger,
        ),
      );
    }
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
              AppLocalizations.of(context).couldNotGetYourGpsLocationCheck,
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: SchoolWayTheme.warning,
          ),
        );
        return;
      }
      final myLoc = LatLng(pos.latitude, pos.longitude);
      setState(() => _myLocation = myLoc);
      _mapController.move(center: myLoc, zoom: 15);
    } finally {
      if (mounted) setState(() => _locatingSelf = false);
    }
  }

  List<RouteWaypoint> _googlePolylinePoints() {
    if (_geometry != null &&
        _geometryStops != null &&
        _geometry!.encodedPolyline.isNotEmpty) {
      final decoded = _geometry!.decodeWaypoints();
      if (decoded.length >= 2) return decoded;
    }
    return const [];
  }

  List<RouteWaypoint> _legacyPolylinePoints() {
    if (_waypoints.length >= 2) {
      return List<RouteWaypoint>.from(_waypoints);
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final googlePolylinePoints = _googlePolylinePoints();
    final legacyPolylinePoints = _legacyPolylinePoints();

    return PopScope(
      canPop: !_inEditor,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _inEditor) {
          _closeEditor();
        }
      },
      child: Scaffold(
        backgroundColor: SchoolWayTheme.background,
        appBar: AppBar(
          backgroundColor: SchoolWayTheme.background,
          elevation: 0,
          foregroundColor: SchoolWayTheme.navy,
          leading: IconButton(
            tooltip: _inEditor ? 'Planned routes' : 'Back',
            icon: Icon(Icons.arrow_back),
            onPressed: () {
              if (_inEditor) {
                _closeEditor();
              } else {
                Navigator.maybePop(context);
              }
            },
          ),
          title: Text(
            _inEditor
                ? (_editingId == null ? 'New route' : 'Edit route')
                : 'Route planner',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w600,
              fontSize: 20,
              color: SchoolWayTheme.navy,
            ),
          ),
          actions: _inEditor
              ? [
                  TextButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            AppLocalizations.of(context).save,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ]
              : [
                  IconButton(
                    tooltip: AppLocalizations.of(context).addRoute,
                    icon: Icon(Icons.add),
                    onPressed: _openEditorForNewRoute,
                  ),
                ],
        ),
        body: _inEditor
            ? _buildEditorBody(googlePolylinePoints, legacyPolylinePoints)
            : _buildPlannedRoutesList(),
      ),
    );
  }

  Widget _buildPlannedRoutesList() {
    return StreamBuilder<List<PlannedRoute>>(
      stream: FirebaseService.getPlannedRoutes(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _plannedRoutesLoadError(context, snap.error);
        }
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        final routes = snap.data!;
        if (routes.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.alt_route,
                    size: 56,
                    color: SchoolWayTheme.blueGrey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context).noPlannedRoutesYet,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      color: SchoolWayTheme.navy,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context).tapInTheTopCornerToDraw,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14,
                      height: 1.4,
                      color: SchoolWayTheme.blueGrey,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: routes.length,
          separatorBuilder: (context, index) => SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = routes[i];
            final hasGoogleGeometry = r.googleGeometry != null;
            return Material(
              color: SchoolWayTheme.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openEditorForRoute(r),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    title: Text(
                      r.name,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${r.editableStops.length} stops'
                      '${hasGoogleGeometry ? ' • Google geometry' : ''}',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13,
                        color: SchoolWayTheme.blueGrey,
                      ),
                    ),
                    trailing: IconButton(
                      icon: Icon(
                        Icons.delete_outline,
                        color: SchoolWayTheme.danger,
                      ),
                      onPressed: () => _confirmDelete(r),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEditorBody(
    List<RouteWaypoint> googlePolylinePoints,
    List<RouteWaypoint> legacyPolylinePoints,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).routeName,
                    hintText: AppLocalizations.of(context).eGRouteA,
                    filled: true,
                    fillColor: SchoolWayTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  style: TextStyle(fontFamily: 'Lexend'),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _durationController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context).durationMin,
                    hintText: AppLocalizations.of(context).text45,
                    filled: true,
                    fillColor: SchoolWayTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  style: TextStyle(fontFamily: 'Lexend'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _editingId == null
                          ? AppLocalizations.of(context).routePlannerTapHint
                          : 'Editing • id: $_editingId',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13,
                        color: SchoolWayTheme.blueGrey,
                      ),
                    ),
                    if (_geometryLoading)
                      Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          AppLocalizations.of(context).updatingRoute,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 11,
                            color: SchoolWayTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _waypoints.isEmpty ? null : _undoLastWaypoint,
                icon: Icon(Icons.undo, size: 18),
                label: Text(
                  AppLocalizations.of(context).undo,
                  style: TextStyle(fontFamily: 'Lexend'),
                ),
              ),
              TextButton.icon(
                onPressed: _waypoints.isEmpty ? null : _clearWaypoints,
                icon: Icon(Icons.clear, size: 18),
                label: Text(
                  AppLocalizations.of(context).clear,
                  style: TextStyle(fontFamily: 'Lexend'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              SchoolWayMap(
                controller: _mapController,
                initialCenter: _initialCenter,
                initialZoom: 12,
                onTap: (lat, lng) => _addWaypoint(LatLng(lat, lng)),
                onCameraChanged: (lat, lng, zoom) => _zoom = zoom,
                markers: [
                  if (_myLocation != null)
                    SchoolWayMapMarker(
                      id: 'planner-my-location',
                      latitude: _myLocation!.latitude,
                      longitude: _myLocation!.longitude,
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
                  for (var i = 0; i < _waypoints.length; i++)
                    SchoolWayMapMarker(
                      id: 'planner-pin-$i',
                      latitude: _waypoints[i].latitude,
                      longitude: _waypoints[i].longitude,
                      width: 48,
                      height: 58,
                      alignment: Alignment.topCenter,
                      child: buildRoutePlannerPinWidget(i + 1),
                    ),
                ],
                googlePolylines: [
                  if (googlePolylinePoints.length >= 2)
                    SchoolWayMapPolyline(
                      id: 'planner-route-google',
                      points: googlePolylinePoints,
                      strokeWidth: 5,
                      color: SchoolWayTheme.primary,
                    ),
                ],
                legacyPolylines: [
                  if (legacyPolylinePoints.length >= 2)
                    SchoolWayMapPolyline(
                      id: 'planner-route-legacy',
                      points: legacyPolylinePoints,
                      strokeWidth: 3,
                      color: SchoolWayTheme.blueGrey.withValues(alpha: 0.5),
                    ),
                ],
                attribution: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const OsmMapAttribution(),
                    Text(
                      AppLocalizations.of(context).googleMapsAttribution,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 10,
                        color: SchoolWayTheme.blueGrey,
                        shadows: [
                          Shadow(
                            color: SchoolWayTheme.surface.withValues(
                              alpha: 0.9,
                            ),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: SchoolWayTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      elevation: 2,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: AppLocalizations.of(context).zoomIn,
                            icon: Icon(
                              Icons.add,
                              color: SchoolWayTheme.primary,
                            ),
                            onPressed: () {
                              _mapController.move(
                                center:
                                    _mapController.lastRequestedCenter ??
                                    _initialCenter,
                                zoom: _zoom + 1,
                              );
                            },
                          ),
                          Divider(height: 1, thickness: 1),
                          IconButton(
                            tooltip: AppLocalizations.of(context).zoomOut,
                            icon: Icon(
                              Icons.remove,
                              color: SchoolWayTheme.primary,
                            ),
                            onPressed: () {
                              _mapController.move(
                                center:
                                    _mapController.lastRequestedCenter ??
                                    _initialCenter,
                                zoom: _zoom - 1,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 12),
                    Material(
                      color: SchoolWayTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      elevation: 2,
                      child: _locatingSelf
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
                              tooltip: AppLocalizations.of(context).myLocation,
                              icon: Icon(
                                Icons.my_location,
                                color: SchoolWayTheme.primary,
                              ),
                              onPressed: _centerOnMyLocation,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _plannedRoutesLoadError(BuildContext context, Object? error) {
  final denied =
      error is FirebaseException && error.code == 'permission-denied';
  final strings = AppLocalizations.of(context);
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            denied ? Icons.lock_outline : Icons.error_outline,
            size: 40,
            color: denied ? SchoolWayTheme.warning : SchoolWayTheme.danger,
          ),
          SizedBox(height: 12),
          Text(
            denied
                ? 'Firestore rules are blocking planned routes'
                : 'Could not load saved routes',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: SchoolWayTheme.navy,
            ),
          ),
          SizedBox(height: 10),
          Text(
            denied ? strings.authorizationError : strings.unavailableError,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13,
              height: 1.4,
              color: denied ? SchoolWayTheme.primary : SchoolWayTheme.text87,
            ),
          ),
        ],
      ),
    ),
  );
}
