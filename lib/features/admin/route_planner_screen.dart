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
          _mapController.move(
            LatLng(first.latitude, first.longitude),
            13,
          );
        } catch (_) {}
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
    } catch (e) {
      debugPrint('OSRM route refresh failed: $e');
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
        RouteWaypoint(
          latitude: latLng.latitude,
          longitude: latLng.longitude,
        ),
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
        const SnackBar(
          content: Text('Enter a route name', style: TextStyle(fontFamily: 'Lexend')),
          backgroundColor: Color(0xFFFF9800),
        ),
      );
      return;
    }
    if (_waypoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tap the map to add at least one stop', style: TextStyle(fontFamily: 'Lexend')),
          backgroundColor: Color(0xFFFF9800),
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
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e', style: const TextStyle(fontFamily: 'Lexend')),
          backgroundColor: Colors.red,
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
      final osrmWaypoints =
          await _fetchOsrmGeometry(tappedWaypoints);
      if (osrmWaypoints.length < 2) return tappedWaypoints;
      return osrmWaypoints;
    } catch (e) {
      debugPrint('OSRM waypoint generation failed, falling back to taps: $e');
      return tappedWaypoints;
    }
  }

  Future<List<RouteWaypoint>> _fetchOsrmGeometry(
    List<RouteWaypoint> viaPoints,
  ) async {
    final coords = viaPoints
        .map((w) => '${w.longitude},${w.latitude}')
        .join(';');

    final radiuses = List<String>.filled(viaPoints.length, 'unlimited').join(';');

    final uri = Uri.parse('$_osrmRouteV1Base/driving/$coords').replace(
      queryParameters: {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'false',
        'continue_straight': 'false',
        'radiuses': radiuses,
      },
    );

    final res = await http.get(uri, headers: const {
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 25));

    if (res.statusCode != 200) {
      throw Exception('OSRM HTTP ${res.statusCode}: ${res.body}');
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final code = decoded['code'] as String?;
    if (code != null && code != 'Ok') {
      throw Exception('OSRM: $code');
    }

    final routes = decoded['routes'] as List<dynamic>? ?? const [];
    if (routes.isEmpty) return const [];

    final geometry = (routes.first as Map<String, dynamic>)['geometry']
        as Map<String, dynamic>?;
    final rawCoords = geometry?['coordinates'] as List<dynamic>?;
    if (rawCoords == null) return const [];

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
        title: const Text('Delete route?', style: TextStyle(fontFamily: 'Lexend')),
        content: Text(
          r.name,
          style: const TextStyle(fontFamily: 'Lexend'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
        const SnackBar(
          content: Text('Route deleted', style: TextStyle(fontFamily: 'Lexend')),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e', style: const TextStyle(fontFamily: 'Lexend')),
          backgroundColor: Colors.red,
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
          const SnackBar(
            content: Text(
              'Could not get your GPS location. Check permission and location settings.',
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: Color(0xFFFF9800),
          ),
        );
        return;
      }
      try {
        final myLoc = LatLng(pos.latitude, pos.longitude);
        setState(() => _myLocation = myLoc);
        _mapController.move(myLoc, 15);
      } catch (_) {}
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
    return const [];
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
        backgroundColor: const Color(0xFFCAF0F8),
        appBar: AppBar(
          backgroundColor: const Color(0xFFCAF0F8),
          elevation: 0,
          foregroundColor: const Color(0xFF03045E),
          leading: IconButton(
            tooltip: _inEditor ? 'Planned routes' : 'Back',
            icon: const Icon(Icons.arrow_back),
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
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w600,
              fontSize: 20,
              color: Color(0xFF03045E),
            ),
          ),
          actions: _inEditor
              ? [
                  TextButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Save',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ]
              : [
                  IconButton(
                    tooltip: 'Add route',
                    icon: const Icon(Icons.add),
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
          return _plannedRoutesLoadError(snap.error);
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
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
                    color: Colors.blueGrey.shade400,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No planned routes yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      color: Color(0xFF03045E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + in the top corner to draw a route on the map.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14,
                      height: 1.4,
                      color: Colors.blueGrey.shade600,
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
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final r = routes[i];
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _openEditorForRoute(r),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    title: Text(
                      r.name,
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${r.editableStops.length} stops',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13,
                        color: Colors.blueGrey.shade600,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
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
                    labelText: 'Route name',
                    hintText: 'e.g. Route A',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  style: const TextStyle(fontFamily: 'Lexend'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _durationController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Duration (min)',
                    hintText: '45',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  style: const TextStyle(fontFamily: 'Lexend'),
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
                        color: Colors.blueGrey.shade700,
                      ),
                    ),
                    if (_osrmLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Updating routeâ€¦',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 11,
                            color: Color(0xFF0077B6),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _waypoints.isEmpty ? null : _undoLastWaypoint,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Undo', style: TextStyle(fontFamily: 'Lexend')),
              ),
              TextButton.icon(
                onPressed: _waypoints.isEmpty ? null : _clearWaypoints,
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Clear', style: TextStyle(fontFamily: 'Lexend')),
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
                  const OsmMapTileLayer(),
                  if (polylinePoints.length >= 2)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: polylinePoints,
                          strokeWidth: showStraightFallback ? 3 : 5,
                          color: showStraightFallback
                              ? Colors.blueGrey.withValues(alpha: 0.5)
                              : const Color(0xFF0077B6),
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
                              color: const Color(0xFF2196F3),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
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
                                  color: const Color(0xFF03045E),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: const [
                                    BoxShadow(
                                      blurRadius: 4,
                                      color: Colors.black26,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    fontFamily: 'Lexend',
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    height: 1.1,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.location_on,
                                color: Color(0xFFD32F2F),
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
                      const OsmMapAttribution(),
                      Text(
                        'OSRM driving • project-osrm.org',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 10,
                          color: const Color(0xFF546E7A),
                          shadows: [
                            Shadow(
                              color: Colors.white.withValues(alpha: 0.9),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      elevation: 2,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Zoom in',
                            icon: const Icon(Icons.add, color: Color(0xFF0077B6)),
                            onPressed: () {
                              final camera = _mapController.camera;
                              _mapController.move(camera.center, camera.zoom + 1);
                            },
                          ),
                          const Divider(height: 1, thickness: 1),
                          IconButton(
                            tooltip: 'Zoom out',
                            icon: const Icon(Icons.remove, color: Color(0xFF0077B6)),
                            onPressed: () {
                              final camera = _mapController.camera;
                              _mapController.move(camera.center, camera.zoom - 1);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      elevation: 2,
                      child: _locatingSelf
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
                              tooltip: 'My location',
                              icon: const Icon(
                                Icons.my_location,
                                color: Color(0xFF0077B6),
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

Widget _plannedRoutesLoadError(Object? error) {
  final msg = error.toString();
  final denied = (error is FirebaseException && error.code == 'permission-denied') ||
      msg.contains('permission-denied');
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            denied ? Icons.lock_outline : Icons.error_outline,
            size: 40,
            color: denied ? const Color(0xFFFF9800) : Colors.red,
          ),
          const SizedBox(height: 12),
          Text(
            denied
                ? 'Firestore rules are blocking planned routes'
                : 'Could not load saved routes',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: Color(0xFF03045E),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            denied
                ? 'Your Firebase project must publish the rules from this app\'s '
                    'firestore.rules file (see match /planned_routes). '
                    'In Firebase Console: Firestore Database â†’ Rules â†’ paste and Publish. '
                    'Or install Firebase CLI and run:\n'
                    'firebase deploy --only firestore:rules'
                : msg,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13,
              height: 1.4,
              color: denied ? const Color(0xFF0077B6) : Colors.black87,
            ),
          ),
        ],
      ),
    ),
  );
}

