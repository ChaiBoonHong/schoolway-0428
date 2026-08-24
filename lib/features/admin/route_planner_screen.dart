import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/widgets/osm_map_attribution.dart';
import 'package:schoolway/core/widgets/osm_map_tile_layer.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/services/location_service.dart';

/// Route planner: tap the map to drop ordered pins; the line follows
/// [OSRM](https://router.project-osrm.org/) driving geometry, refreshed as
/// stops change.
class RoutePlannerScreen extends StatefulWidget {
  const RoutePlannerScreen({super.key});

  static const routeName = '/admin/route-planner';

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  static const LatLng _initialCenter = LatLng(3.1390, 101.6869);
  static const Duration _osrmDebounce = Duration(milliseconds: 180);
  static const String _osrmRouteV1Base =
      'https://router.project-osrm.org/route/v1';

  final MapController _mapController = MapController();
  final _nameController = TextEditingController();
  final _durationController = TextEditingController(text: '45');

  Timer? _osrmDebounceTimer;
  int _osrmGeneration = 0;

  bool _inEditor = false;

  String? _editingId;
  DateTime _routeCreatedAt = DateTime.now();
  final List<RouteWaypoint> _waypoints = [];

  /// Full road geometry from OSRM for current [_waypoints] (debounced).
  List<RouteWaypoint>? _osrmLine;

  /// Waypoint list that [_osrmLine] was computed for (for save + stale checks).
  List<RouteWaypoint>? _osrmLineStops;

  bool _osrmLoading = false;
  bool _saving = false;
  bool _locatingSelf = false;
  LatLng? _myLocation;

  @override
  void dispose() {
    _osrmDebounceTimer?.cancel();
    _nameController.dispose();
    _durationController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _newRoute() {
    _osrmDebounceTimer?.cancel();
    setState(() {
      _inEditor = true;
      _editingId = null;
      _nameController.clear();
      _durationController.text = '45';
      _routeCreatedAt = DateTime.now();
      _waypoints.clear();
      _osrmLine = null;
      _osrmLineStops = null;
      _osrmLoading = false;
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
    _osrmDebounceTimer?.cancel();
    setState(() {
      _inEditor = true;
      _editingId = r.id;
      _nameController.text = r.name;
      _durationController.text = r.expectedDurationMinutes.toString();
      _routeCreatedAt = r.createdAt;
      _waypoints.clear();
      _waypoints.addAll(stops);
      if (_waypoints.length >= 2) {
        _osrmLine = List<RouteWaypoint>.from(r.waypoints);
        _osrmLineStops = List<RouteWaypoint>.from(stops);
      } else {
        _osrmLine = null;
        _osrmLineStops = null;
      }
      _osrmLoading = stops.length >= 2;
    });
    if (stops.isNotEmpty) {
      final first = stops.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(LatLng(first.latitude, first.longitude), 13);
        } catch (error, stackTrace) {
          AppLogger.warning(
            'data',
            'Malformed or unavailable optional data was ignored.',
            error: error,
            stackTrace: stackTrace,
          );
        }
      });
    }
    if (stops.length >= 2) {
      _scheduleOsrmRefresh();
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

  void _scheduleOsrmRefresh() {
    _osrmDebounceTimer?.cancel();
    _osrmDebounceTimer = Timer(_osrmDebounce, _runOsrmRefresh);
  }

  Future<void> _runOsrmRefresh() async {
    final gen = ++_osrmGeneration;
    final stopsSnapshot = List<RouteWaypoint>.from(_waypoints);

    if (stopsSnapshot.length < 2) {
      if (!mounted || gen != _osrmGeneration) return;
      setState(() {
        _osrmLine = null;
        _osrmLineStops = null;
        _osrmLoading = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _osrmLoading = true);
    }

    try {
      final line = await _fetchOsrmGeometry(stopsSnapshot);
      if (!mounted || gen != _osrmGeneration) return;
      if (!_sameStops(stopsSnapshot, _waypoints)) return;

      setState(() {
        if (line.length >= 2) {
          _osrmLine = line;
          _osrmLineStops = List<RouteWaypoint>.from(stopsSnapshot);
        } else {
          _osrmLine = List<RouteWaypoint>.from(stopsSnapshot);
          _osrmLineStops = List<RouteWaypoint>.from(stopsSnapshot);
        }
        _osrmLoading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.warning(
        'routes',
        'Driving route refresh failed; a straight route was used.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || gen != _osrmGeneration) return;
      if (!_sameStops(stopsSnapshot, _waypoints)) return;
      setState(() {
        _osrmLine = List<RouteWaypoint>.from(stopsSnapshot);
        _osrmLineStops = List<RouteWaypoint>.from(stopsSnapshot);
        _osrmLoading = false;
      });
    }
  }

  void _addWaypoint(LatLng latLng) {
    setState(() {
      _waypoints.add(
        RouteWaypoint(latitude: latLng.latitude, longitude: latLng.longitude),
      );
    });
    _scheduleOsrmRefresh();
  }

  void _undoLastWaypoint() {
    if (_waypoints.isEmpty) return;
    setState(() => _waypoints.removeLast());
    _scheduleOsrmRefresh();
  }

  void _clearWaypoints() {
    if (_waypoints.isEmpty) return;
    _osrmDebounceTimer?.cancel();
    setState(() {
      _waypoints.clear();
      _osrmLine = null;
      _osrmLineStops = null;
      _osrmLoading = false;
    });
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

      List<RouteWaypoint> waypointsToSave;
      if (tapped.length >= 2 &&
          _osrmLine != null &&
          _osrmLine!.length >= 2 &&
          _osrmLineStops != null &&
          _sameStops(tapped, _osrmLineStops!)) {
        waypointsToSave = List<RouteWaypoint>.from(_osrmLine!);
      } else {
        waypointsToSave = await _generateWaypointsFromOsrmOrFallback(tapped);
      }

      final duration = int.tryParse(_durationController.text.trim()) ?? 45;

      final route = PlannedRoute(
        id: _editingId ?? '',
        name: name,
        stops: tapped,
        waypoints: waypointsToSave,
        createdAt: _routeCreatedAt,
        updatedAt: wasNew ? null : DateTime.now(),
        expectedDurationMinutes: duration,
      );
      final id = await FirebaseService.savePlannedRoute(route);
      if (!mounted) return;
      setState(() {
        _editingId = id;
        if (waypointsToSave.length >= 2) {
          _osrmLine = waypointsToSave;
          _osrmLineStops = List<RouteWaypoint>.from(tapped);
        }
      });
      if (tapped.length >= 2) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scheduleOsrmRefresh();
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

  Future<List<RouteWaypoint>> _generateWaypointsFromOsrmOrFallback(
    List<RouteWaypoint> tappedWaypoints,
  ) async {
    if (tappedWaypoints.length < 2) return tappedWaypoints;

    try {
      final osrmWaypoints = await _fetchOsrmGeometry(tappedWaypoints);
      if (osrmWaypoints.length < 2) return tappedWaypoints;
      return osrmWaypoints;
    } catch (error, stackTrace) {
      AppLogger.warning(
        'routes',
        'Waypoint generation failed; selected map points were retained.',
        error: error,
        stackTrace: stackTrace,
      );
      return tappedWaypoints;
    }
  }

  Future<List<RouteWaypoint>> _fetchOsrmGeometry(
    List<RouteWaypoint> viaPoints,
  ) async {
    final coords = viaPoints
        .map((w) => '${w.longitude},${w.latitude}')
        .join(';');

    final radiuses = List<String>.filled(
      viaPoints.length,
      'unlimited',
    ).join(';');

    final uri = Uri.parse('$_osrmRouteV1Base/driving/$coords').replace(
      queryParameters: {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'false',
        'continue_straight': 'false',
        'radiuses': radiuses,
      },
    );

    final res = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(Duration(seconds: 25));

    if (res.statusCode != 200) {
      throw Exception('OSRM HTTP ${res.statusCode}: ${res.body}');
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final code = decoded['code'] as String?;
    if (code != null && code != 'Ok') {
      throw Exception('OSRM: $code');
    }

    final routes = decoded['routes'] as List<dynamic>? ?? [];
    if (routes.isEmpty) return [];

    final geometry =
        (routes.first as Map<String, dynamic>)['geometry']
            as Map<String, dynamic>?;
    final rawCoords = geometry?['coordinates'] as List<dynamic>?;
    if (rawCoords == null) return [];

    return rawCoords.map<RouteWaypoint>((p) {
      final pair = p as List<dynamic>;
      final lon = (pair[0] as num).toDouble();
      final lat = (pair[1] as num).toDouble();
      return RouteWaypoint(latitude: lat, longitude: lon);
    }).toList();
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
      try {
        final myLoc = LatLng(pos.latitude, pos.longitude);
        setState(() => _myLocation = myLoc);
        _mapController.move(myLoc, 15);
      } catch (error, stackTrace) {
        AppLogger.warning(
          'data',
          'Malformed or unavailable optional data was ignored.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    } finally {
      if (mounted) setState(() => _locatingSelf = false);
    }
  }

  List<LatLng> _polylinePointsForMap() {
    if (_osrmLine != null && _osrmLine!.length >= 2) {
      return _osrmLine!.map((w) => LatLng(w.latitude, w.longitude)).toList();
    }
    if (_waypoints.length >= 2) {
      return _waypoints.map((w) => LatLng(w.latitude, w.longitude)).toList();
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final polylinePoints = _polylinePointsForMap();
    final showStraightFallback =
        _waypoints.length >= 2 && (_osrmLine == null || _osrmLine!.length < 2);

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
            ? _buildEditorBody(polylinePoints, showStraightFallback)
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
                      '${r.editableStops.length} stops',
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
    List<LatLng> polylinePoints,
    bool showStraightFallback,
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
                          ? 'Tap map: pins 1 -> 2 -> 3... OSRM follows drivable roads.'
                          : 'Editing • id: $_editingId',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13,
                        color: SchoolWayTheme.blueGrey,
                      ),
                    ),
                    if (_osrmLoading)
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
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _initialCenter,
                  initialZoom: 12,
                  onTap: (tapPos, latLng) => _addWaypoint(latLng),
                ),
                children: [
                  OsmMapTileLayer(),
                  if (polylinePoints.length >= 2)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: polylinePoints,
                          strokeWidth: showStraightFallback ? 3 : 5,
                          color: showStraightFallback
                              ? SchoolWayTheme.blueGrey.withValues(alpha: 0.5)
                              : SchoolWayTheme.primary,
                        ),
                      ],
                    ),
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
                      for (var i = 0; i < _waypoints.length; i++)
                        Marker(
                          point: LatLng(
                            _waypoints[i].latitude,
                            _waypoints[i].longitude,
                          ),
                          width: 48,
                          height: 58,
                          // flutter_map: topCenter = geographic [point] at the
                          // bottom-center of this box (widget sits above the tap).
                          // bottomCenter would anchor the tip wrong and stack pins.
                          alignment: Alignment.topCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: SchoolWayTheme.navy,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      blurRadius: 4,
                                      color: SchoolWayTheme.text26,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    height: 1.1,
                                    color: SchoolWayTheme.surface,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.location_on,
                                color: SchoolWayTheme.danger,
                                size: 32,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OsmMapAttribution(),
                      Text(
                        AppLocalizations.of(context).osrmDrivingProjectOsrmOrg,
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
                              final camera = _mapController.camera;
                              _mapController.move(
                                camera.center,
                                camera.zoom + 1,
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
                              final camera = _mapController.camera;
                              _mapController.move(
                                camera.center,
                                camera.zoom - 1,
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
