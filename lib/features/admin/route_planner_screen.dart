import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'dart:async';

import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/map/map_markers.dart';
import 'package:schoolway/core/map/schoolway_map.dart';
import 'package:schoolway/core/map/schoolway_map_controller.dart';
import 'package:schoolway/features/admin/widgets/route_stops_panel.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/services/location_service.dart';
import 'package:schoolway/services/routes_api_service.dart';
import 'package:schoolway/services/school_config_service.dart';

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
  static const LatLng _initialCenter =
      SchoolConfigService.defaultRouteSchoolLocation;
  static const Duration _geometryDebounce = Duration(milliseconds: 250);

  final SchoolWayMapController _mapController = SchoolWayMapController();
  final _nameController = TextEditingController();

  Timer? _geometryDebounceTimer;
  int _geometryGeneration = 0;

  bool _inEditor = false;
  bool _showStopsPanel = false;

  String? _editingId;
  DateTime _routeCreatedAt = DateTime.now();
  final List<RouteWaypoint> _waypoints = [];

  /// Full road geometry from Google for current [_waypoints] (debounced).
  GoogleRouteGeometry? _geometry;

  /// Waypoint list that [_geometry] was computed for (for save + stale checks).
  List<RouteWaypoint>? _geometryStops;

  /// Stops as loaded from the saved doc, to detect reorder/remove on save.
  List<RouteWaypoint>? _loadedStops;
  RouteWaypoint? _schoolEndpoint;

  bool _geometryLoading = false;
  bool _saving = false;
  bool _locatingSelf = false;
  DateTime _ignoreMapTapsUntil = DateTime.fromMillisecondsSinceEpoch(0);
  LatLng? _myLocation;
  double _zoom = 12;

  void _temporarilyIgnoreMapTaps([
    Duration duration = const Duration(milliseconds: 750),
  ]) {
    _ignoreMapTapsUntil = DateTime.now().add(duration);
  }

  int get _computedDurationMinutes {
    if (_geometry?.durationSeconds != null && _geometry!.durationSeconds! > 0) {
      final minutes = (_geometry!.durationSeconds! / 60).round();
      return minutes < 1 ? 1 : minutes;
    }
    if (_waypoints.length >= 2) {
      final minutes = (_waypoints.length - 1) * 3;
      return minutes < 5 ? 5 : minutes;
    }
    return 15;
  }

  String get _formattedDistance {
    if (_geometry?.distanceMeters != null && _geometry!.distanceMeters! > 0) {
      final km = _geometry!.distanceMeters! / 1000.0;
      return '${km.toStringAsFixed(1)} km';
    }
    return '';
  }

  @override
  void dispose() {
    _geometryDebounceTimer?.cancel();
    _nameController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _newRoute(RouteWaypoint schoolEndpoint) {
    _geometryDebounceTimer?.cancel();
    setState(() {
      _inEditor = true;
      _showStopsPanel = false;
      _editingId = null;
      _nameController.clear();
      _routeCreatedAt = DateTime.now();
      _waypoints
        ..clear()
        ..add(schoolEndpoint);
      _schoolEndpoint = schoolEndpoint;
      _geometry = null;
      _geometryStops = null;
      _loadedStops = null;
      _geometryLoading = false;
    });
  }

  Future<RouteWaypoint?> _loadSchoolEndpoint() async {
    final school = await SchoolConfigService.getRoutePlannerSchoolLocation();
    return RouteWaypoint(
      latitude: school.latitude,
      longitude: school.longitude,
    );
  }

  void _showMissingSchoolLocation() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context).routeSchoolLocationRequired,
          style: TextStyle(fontFamily: 'Lexend'),
        ),
        backgroundColor: SchoolWayTheme.warning,
      ),
    );
  }

  Future<void> _openEditorForNewRoute() async {
    final schoolEndpoint = await _loadSchoolEndpoint();
    if (!mounted || schoolEndpoint == null) return;
    _newRoute(schoolEndpoint);
  }

  Future<void> _openEditorForRoute(PlannedRoute r) async {
    final schoolEndpoint = await _loadSchoolEndpoint();
    if (!mounted || schoolEndpoint == null) return;
    _loadRoute(r, schoolEndpoint);
  }

  void _closeEditor() {
    setState(() => _inEditor = false);
  }

  void _loadRoute(PlannedRoute r, RouteWaypoint schoolEndpoint) {
    final stops = ensureSchoolRouteEndpoint(r.editableStops, schoolEndpoint);
    _geometryDebounceTimer?.cancel();
    setState(() {
      _inEditor = true;
      _showStopsPanel = false;
      _editingId = r.id;
      _schoolEndpoint = schoolEndpoint;
      _nameController.text = r.name;
      _routeCreatedAt = r.createdAt;
      _waypoints.clear();
      _waypoints.addAll(stops);
      _loadedStops = List<RouteWaypoint>.from(stops);
      final geometry = r.googleGeometry;
      if (stops.length >= 2 &&
          geometry != null &&
          _sameStops(r.editableStops, stops)) {
        _geometry = geometry;
        _geometryStops = List<RouteWaypoint>.from(stops);
      } else {
        _geometry = null;
        _geometryStops = null;
      }
      _geometryLoading =
          stops.length >= 2 && stops.length <= maxPlannedRouteStops;
    });
    if (stops.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitRouteBounds();
      });
    }
    if (stops.length >= 2 && stops.length <= maxPlannedRouteStops) {
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
    final isFirstPreview = _geometry == null && _waypoints.length >= 2;
    final delay = isFirstPreview ? Duration.zero : _geometryDebounce;
    _geometryDebounceTimer = Timer(delay, _runGeometryRefresh);
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

    if (stopsSnapshot.length > maxPlannedRouteStops) {
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
    if (_locatingSelf || DateTime.now().isBefore(_ignoreMapTapsUntil)) {
      return;
    }
    if (_waypoints.length >= maxPlannedRouteStops) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).routeMaxStopsReached(maxPlannedRouteStops),
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: SchoolWayTheme.warning,
        ),
      );
      return;
    }
    setState(() {
      final waypoint = RouteWaypoint(
        latitude: latLng.latitude,
        longitude: latLng.longitude,
      );
      if (_schoolEndpoint == null) {
        _waypoints.add(waypoint);
      } else {
        _waypoints.insert(_waypoints.length - 1, waypoint);
      }
      if (_waypoints.length >= 2) {
        _geometryLoading = true;
      }
    });
    _scheduleGeometryRefresh();
  }

  void _reorderWaypoints(int oldIndex, int newIndex) {
    final schoolIndex = _schoolEndpoint == null ? -1 : _waypoints.length - 1;
    if (oldIndex < 0 ||
        oldIndex >= _waypoints.length ||
        newIndex < 0 ||
        newIndex >= _waypoints.length ||
        oldIndex == schoolIndex ||
        newIndex == schoolIndex) {
      return;
    }
    setState(() {
      final stop = _waypoints.removeAt(oldIndex);
      _waypoints.insert(newIndex, stop);
      if (_waypoints.length >= 2) {
        _geometryLoading = true;
      }
    });
    _scheduleGeometryRefresh();
  }

  void _removeWaypointAt(int index) {
    if (index < 0 || index >= _waypoints.length) return;
    if (_schoolEndpoint != null && index == _waypoints.length - 1) return;
    _temporarilyIgnoreMapTaps();
    setState(() {
      _waypoints.removeAt(index);
      if (_waypoints.length >= 2) {
        _geometryLoading = true;
      } else {
        _geometry = null;
        _geometryStops = null;
        _geometryLoading = false;
      }
    });
    _scheduleGeometryRefresh();
  }

  void _centerOnStop(int index) {
    if (index < 0 || index >= _waypoints.length) return;
    _temporarilyIgnoreMapTaps();
    final stop = _waypoints[index];
    _mapController.move(
      center: LatLng(stop.latitude, stop.longitude),
      zoom: _zoom < 14 ? 15 : _zoom,
    );
  }

  void _undoLastWaypoint() {
    final removableIndex = _schoolEndpoint == null
        ? _waypoints.length - 1
        : _waypoints.length - 2;
    if (removableIndex < 0) return;
    _temporarilyIgnoreMapTaps();
    setState(() {
      _waypoints.removeAt(removableIndex);
      if (_waypoints.length >= 2) {
        _geometryLoading = true;
      } else {
        _geometry = null;
        _geometryStops = null;
        _geometryLoading = false;
      }
    });
    _scheduleGeometryRefresh();
  }

  void _clearWaypoints() {
    if (_waypoints.isEmpty ||
        (_schoolEndpoint != null && _waypoints.length == 1)) {
      return;
    }
    _temporarilyIgnoreMapTaps();
    _geometryDebounceTimer?.cancel();
    setState(() {
      _waypoints
        ..clear()
        ..addAll(_schoolEndpoint == null ? const [] : [_schoolEndpoint!]);
      _geometry = null;
      _geometryStops = null;
      _geometryLoading = false;
    });
  }

  void _fitRouteBounds() {
    _temporarilyIgnoreMapTaps();
    final points = _googlePolylinePoints();
    final allPoints = <RouteWaypoint>[...points, ..._waypoints];
    if (allPoints.isEmpty) return;
    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;
    for (final p in allPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController.fitBounds(
      southLatitude: minLat,
      westLongitude: minLng,
      northLatitude: maxLat,
      eastLongitude: maxLng,
      padding: 64,
    );
  }

  /// True when the save must not proceed: editing a saved route whose stop
  /// positions shifted while students reference those positions, and the
  /// admin declined the impact warning. Pure appends keep every existing
  /// index valid and never prompt.
  Future<bool> _stopShiftUnconfirmed(List<RouteWaypoint> tapped) async {
    final loaded = _loadedStops;
    final routeId = _editingId;
    if (routeId == null || routeId.isEmpty || loaded == null) return false;

    var shifted = false;
    final overlap = loaded.length < tapped.length
        ? loaded.length
        : tapped.length;
    for (var i = 0; i < overlap; i++) {
      if (loaded[i].latitude != tapped[i].latitude ||
          loaded[i].longitude != tapped[i].longitude) {
        shifted = true;
        break;
      }
    }
    if (!shifted) return false;

    final (students, _) = await FirebaseService.countRouteDependents(routeId);
    if (students == 0) return false;
    if (!mounted) return true;

    final strings = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          strings.routeSaveShiftWarningTitle,
          style: TextStyle(fontFamily: 'Lexend'),
        ),
        content: Text(
          strings.routeSaveShiftWarningBody(students),
          style: TextStyle(fontFamily: 'Lexend', height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              strings.saveAnyway,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w600,
                color: SchoolWayTheme.warning,
              ),
            ),
          ),
        ],
      ),
    );
    return confirmed != true;
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
    final schoolEndpoint = _schoolEndpoint;
    if (schoolEndpoint == null) {
      _showMissingSchoolLocation();
      return;
    }
    if (_waypoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).routeMinTwoStops,
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
      final tapped = ensureSchoolRouteEndpoint(_waypoints, schoolEndpoint);
      if (tapped.length > maxPlannedRouteStops) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              ).routeSchoolEndpointExceedsLimit(maxPlannedRouteStops),
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: SchoolWayTheme.warning,
          ),
        );
        return;
      }

      if (await _stopShiftUnconfirmed(tapped)) return;

      final geometry = await _computeGeometryForSave(tapped);
      final geometryWaypoints =
          geometry?.decodeWaypoints() ?? const <RouteWaypoint>[];
      final waypointsToSave = geometryWaypoints.length >= 2
          ? geometryWaypoints
          : tapped;

      final autoDuration =
          geometry?.durationSeconds != null && geometry!.durationSeconds! > 0
          ? (geometry.durationSeconds! / 60).round().clamp(1, 480)
          : _computedDurationMinutes;

      final route = PlannedRoute(
        id: _editingId ?? '',
        name: name,
        stops: tapped,
        waypoints: waypointsToSave,
        createdAt: _routeCreatedAt,
        updatedAt: wasNew ? null : DateTime.now(),
        expectedDurationMinutes: autoDuration,
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
            wasNew
                ? AppLocalizations.of(context).routeCreated
                : AppLocalizations.of(context).routeSaved,
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
            AppLocalizations.of(context).saveFailedWithError('$e'),
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
        setState(() {
          _inEditor = false;
          _showStopsPanel = false;
          _editingId = null;
          _nameController.clear();
          _waypoints.clear();
          _schoolEndpoint = null;
          _geometry = null;
          _geometryStops = null;
          _loadedStops = null;
          _geometryLoading = false;
        });
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
            AppLocalizations.of(context).deleteFailedWithError('$e'),
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: SchoolWayTheme.danger,
        ),
      );
    }
  }

  /// Asks where to split [r], then creates two connected routes from its
  /// ordered stops, migrates referencing students/buses, and removes the
  /// original only after everything succeeds.
  Future<void> _confirmSplit(PlannedRoute r) async {
    final strings = AppLocalizations.of(context);
    final stops = r.editableStops;
    if (stops.length < 4) return;

    if (await FirebaseService.hasActiveSessionForRoute(r.id)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.routeSplitBlockedActiveTrip,
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: SchoolWayTheme.warning,
        ),
      );
      return;
    }

    final (studentCount, busCount) = await FirebaseService.countRouteDependents(
      r.id,
    );
    if (!mounted) return;

    var splitAfter = stops.length ~/ 2;
    if (splitAfter < 2) splitAfter = 2;
    var shareJunction = true;
    var busTargetPart = busCount > 0 ? 1 : 0;

    final choice = await showDialog<(int, bool, int)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final plan = planRouteSplit(
            stops,
            splitAfter,
            shareJunctionStop: shareJunction,
          );
          final valid = plan != null && splitAfter >= 2;
          return AlertDialog(
            title: Text(
              strings.routeSplitDialogTitle,
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            content: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.name} • '
                      '${strings.routeStopCounter(stops.length, maxPlannedRouteStops)}',
                      style: TextStyle(fontFamily: 'Lexend', fontSize: 13),
                    ),
                    SizedBox(height: 12),
                    Text(
                      strings.routeSplitAfterLabel(splitAfter),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Slider(
                      min: 2,
                      max: (stops.length - 2).toDouble(),
                      divisions: stops.length > 4 ? stops.length - 3 : null,
                      value: splitAfter.toDouble(),
                      label: '$splitAfter',
                      onChanged: (value) =>
                          setDialogState(() => splitAfter = value.round()),
                    ),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        strings.routeShareJunctionLabel(splitAfter),
                        style: TextStyle(fontFamily: 'Lexend', fontSize: 13),
                      ),
                      value: shareJunction,
                      onChanged: (value) =>
                          setDialogState(() => shareJunction = value ?? true),
                    ),
                    if (studentCount > 0 || busCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          strings.routeSplitDependentsInfo(
                            studentCount,
                            busCount,
                          ),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                            height: 1.35,
                            color: SchoolWayTheme.blueGrey,
                          ),
                        ),
                      ),
                    if (busCount > 0) ...[
                      SizedBox(height: 4),
                      Text(
                        strings.routeSplitBusTargetLabel,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      RadioGroup<int>(
                        groupValue: busTargetPart,
                        onChanged: (value) =>
                            setDialogState(() => busTargetPart = value ?? 1),
                        child: Column(
                          children: [
                            RadioListTile<int>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: 1,
                              title: Text(
                                strings.routePartName(1),
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                            RadioListTile<int>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: 2,
                              title: Text(
                                strings.routePartName(2),
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                            RadioListTile<int>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: 0,
                              title: Text(
                                strings.routeSplitKeepUnassigned,
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 8),
                    Text(
                      valid
                          ? strings.routeSplitPreview(
                              plan.first.length,
                              plan.second.length,
                            )
                          : strings.routeSplitOptionsInvalid(
                              maxPlannedRouteStops,
                            ),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: valid
                            ? SchoolWayTheme.primary
                            : SchoolWayTheme.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(strings.cancel),
              ),
              TextButton(
                onPressed: valid
                    ? () => Navigator.pop(ctx, (
                        splitAfter,
                        shareJunction,
                        busTargetPart,
                      ))
                    : null,
                child: Text(
                  strings.routeSplitConfirm,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    color: valid ? SchoolWayTheme.primary : null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (choice == null || !mounted) return;
    await _performSplit(r, choice.$1, choice.$2, choice.$3);
  }

  Future<void> _performSplit(
    PlannedRoute r,
    int splitAfter,
    bool shareJunction,
    int busTargetPart,
  ) async {
    final strings = AppLocalizations.of(context);
    final schoolEndpoint = await _loadSchoolEndpoint();
    if (!mounted || schoolEndpoint == null) return;
    final plan = planRouteSplit(
      r.editableStops,
      splitAfter,
      shareJunctionStop: shareJunction,
    );
    if (plan == null) return;
    final splitParts = [
      ensureSchoolRouteEndpoint(plan.first, schoolEndpoint),
      ensureSchoolRouteEndpoint(plan.second, schoolEndpoint),
    ];
    if (splitParts.any((part) => part.length > maxPlannedRouteStops)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            strings.routeSchoolEndpointExceedsLimit(maxPlannedRouteStops),
          ),
          backgroundColor: SchoolWayTheme.warning,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                strings.routeSplitting,
                style: TextStyle(fontFamily: 'Lexend'),
              ),
            ),
          ],
        ),
      ),
    );

    final savedIds = <String>[];
    final createdNames = <String>[];
    try {
      // Compute Google geometry for both parts before touching Firestore so
      // the original — the sole holder of road-level geometry — is never
      // replaced by straight-line tap data.
      final geometries = <GoogleRouteGeometry>[];
      for (final part in splitParts) {
        final geometry = await _computeGeometryForSave(part);
        if (geometry == null) {
          throw const RouteGeometryUnavailableException();
        }
        geometries.add(geometry);
      }

      for (var i = 0; i < 2; i++) {
        final part = splitParts[i];
        final geometry = geometries[i];
        final decoded = geometry.decodeWaypoints();
        final name = '${r.name} — ${strings.routePartName(i + 1)}';
        final route = PlannedRoute(
          id: '',
          name: name,
          stops: List<RouteWaypoint>.from(part),
          waypoints: decoded.length >= 2
              ? decoded
              : List<RouteWaypoint>.from(part),
          createdAt: DateTime.now(),
          expectedDurationMinutes: r.expectedDurationMinutes,
          googleGeometry: geometry,
        );
        savedIds.add(await FirebaseService.savePlannedRoute(route));
        createdNames.add(name);
      }

      final migration = await FirebaseService.migrateAssignmentsAfterSplit(
        oldRouteId: r.id,
        firstRouteId: savedIds[0],
        firstRouteName: createdNames[0],
        secondRouteId: savedIds[1],
        secondRouteName: createdNames[1],
        plan: plan,
        busTargetPart: busTargetPart,
      );

      await FirebaseService.deletePlannedRoute(r.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.routeSplitDone(createdNames.first, createdNames.last),
                style: TextStyle(fontFamily: 'Lexend'),
              ),
              if (migration.migratedStudents > 0 || migration.migratedBuses > 0)
                Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    strings.routeSplitMigratedSummary(
                      migration.migratedStudents,
                      migration.migratedBuses,
                    ),
                    style: TextStyle(fontFamily: 'Lexend', fontSize: 12),
                  ),
                ),
              if (migration.crossPartStudents > 0)
                Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    strings.routeSplitCrossPartWarning(
                      migration.crossPartStudents,
                    ),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          backgroundColor: SchoolWayTheme.success,
        ),
      );
    } catch (e) {
      for (final id in savedIds) {
        try {
          await FirebaseService.deletePlannedRoute(id);
        } catch (cleanupError, cleanupStack) {
          AppLogger.warning(
            'routes',
            'Route split rollback could not delete a partially created route.',
            error: cleanupError,
            stackTrace: cleanupStack,
          );
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is RouteGeometryUnavailableException
                ? strings.routeGeometryFailedKeepOriginal
                : strings.routeSplitFailed('$e'),
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: e is RouteGeometryUnavailableException
              ? SchoolWayTheme.warning
              : SchoolWayTheme.danger,
        ),
      );
    }
  }

  Future<void> _centerOnMyLocation() async {
    if (_locatingSelf) return;
    _temporarilyIgnoreMapTaps(const Duration(milliseconds: 1500));
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
      _temporarilyIgnoreMapTaps(const Duration(milliseconds: 1500));
      await _mapController.move(center: myLoc, zoom: 15);
    } finally {
      if (mounted) {
        setState(() => _locatingSelf = false);
        _temporarilyIgnoreMapTaps(const Duration(milliseconds: 800));
      }
    }
  }

  List<RouteWaypoint> _googlePolylinePoints() {
    if (_geometry != null &&
        _geometryStops != null &&
        _geometry!.encodedPolyline.isNotEmpty &&
        _sameStops(_waypoints, _geometryStops!)) {
      final decoded = _geometry!.decodeWaypoints();
      if (decoded.length >= 2) return decoded;
    }
    if (_waypoints.length >= 2) {
      return _waypoints;
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final googlePolylinePoints = _googlePolylinePoints();

    return PopScope(
      canPop: !_inEditor,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _inEditor) {
          _closeEditor();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          leading: IconButton(
            tooltip: _inEditor
                ? AppLocalizations.of(context).plannedRoutesLabel
                : AppLocalizations.of(context).backTooltip,
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
                ? (_editingId == null
                      ? AppLocalizations.of(context).newRouteTitle
                      : AppLocalizations.of(context).editRouteTitle)
                : AppLocalizations.of(context).routePlannerTitle,
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
                    onPressed: () => unawaited(_openEditorForNewRoute()),
                  ),
                ],
        ),
        body: _inEditor
            ? _buildEditorBody(googlePolylinePoints)
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
            final distStr =
                (r.googleGeometry?.distanceMeters != null &&
                    r.googleGeometry!.distanceMeters! > 0)
                ? '${(r.googleGeometry!.distanceMeters! / 1000).toStringAsFixed(1)} km • '
                : '';
            final durationStr = '${r.expectedDurationMinutes} min';

            return Material(
              color: SchoolWayTheme.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => unawaited(_openEditorForRoute(r)),
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
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: SchoolWayTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.alt_route,
                        color: SchoolWayTheme.primary,
                      ),
                    ),
                    title: Text(
                      r.name,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${r.editableStops.length} stops • $distStr$durationStr'
                      '${hasGoogleGeometry ? ' • Drive route' : ''}',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13,
                        color: SchoolWayTheme.blueGrey,
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      tooltip: AppLocalizations.of(context).moreOptionsTooltip,
                      onSelected: (value) {
                        if (value == 'split') {
                          _confirmSplit(r);
                        } else if (value == 'delete') {
                          _confirmDelete(r);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'split',
                          enabled: r.editableStops.length >= 4,
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.call_split,
                              color: SchoolWayTheme.primary,
                            ),
                            title: Text(
                              AppLocalizations.of(context).routeSplitMenuTitle,
                              style: TextStyle(fontFamily: 'Lexend'),
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.delete_outline,
                              color: SchoolWayTheme.danger,
                            ),
                            title: Text(
                              AppLocalizations.of(context).deleteRoute,
                              style: TextStyle(fontFamily: 'Lexend'),
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildEditorBody(List<RouteWaypoint> googlePolylinePoints) {
    final strings = AppLocalizations.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: BoxDecoration(
            color: SchoolWayTheme.surface,
            border: Border(
              bottom: BorderSide(color: SchoolWayTheme.border, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: strings.routeName,
                  hintText: strings.eGRouteA,
                  prefixIcon: Icon(
                    Icons.alt_route,
                    color: SchoolWayTheme.primary,
                  ),
                  filled: true,
                  fillColor: SchoolWayTheme.background.withValues(alpha: 0.3),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                style: TextStyle(fontFamily: 'Lexend'),
              ),
              SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _waypoints.length < 2
                      ? SchoolWayTheme.primary.withValues(alpha: 0.08)
                      : (_geometryLoading
                            ? SchoolWayTheme.accent.withValues(alpha: 0.12)
                            : SchoolWayTheme.success.withValues(alpha: 0.12)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _waypoints.length < 2
                        ? SchoolWayTheme.border
                        : (_geometryLoading
                              ? SchoolWayTheme.accent
                              : SchoolWayTheme.success.withValues(alpha: 0.4)),
                  ),
                ),
                child: Row(
                  children: [
                    if (_geometryLoading) ...[
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: SchoolWayTheme.accent,
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          strings.routeCalculatingBestRoute,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: SchoolWayTheme.primary,
                          ),
                        ),
                      ),
                    ] else if (_waypoints.length < 2) ...[
                      Icon(
                        Icons.touch_app,
                        size: 16,
                        color: SchoolWayTheme.primary,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          strings.routeMinTwoStops,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                            color: SchoolWayTheme.blueGrey,
                          ),
                        ),
                      ),
                    ] else ...[
                      Icon(
                        Icons.directions_car,
                        size: 16,
                        color: SchoolWayTheme.success,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${strings.routeAutoDurationDistance(_computedDurationMinutes, _formattedDistance.isNotEmpty ? _formattedDistance.replaceAll(' km', '') : '0.0')} • ${_waypoints.length} stops',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: SchoolWayTheme.navy,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _waypoints.isEmpty
                          ? null
                          : () => setState(
                              () => _showStopsPanel = !_showStopsPanel,
                            ),
                      icon: Icon(Icons.format_list_numbered, size: 18),
                      label: Text(
                        '${strings.routeStopsPanelTitle} (${_waypoints.length})',
                        style: TextStyle(fontFamily: 'Lexend'),
                      ),
                    ),
                    SizedBox(width: 4),
                    TextButton.icon(
                      onPressed:
                          _waypoints.length <= (_schoolEndpoint == null ? 0 : 1)
                          ? null
                          : _undoLastWaypoint,
                      icon: Icon(Icons.undo, size: 18),
                      label: Text(
                        strings.undo,
                        style: TextStyle(fontFamily: 'Lexend'),
                      ),
                    ),
                    SizedBox(width: 4),
                    TextButton.icon(
                      onPressed:
                          _waypoints.length <= (_schoolEndpoint == null ? 0 : 1)
                          ? null
                          : _clearWaypoints,
                      icon: Icon(Icons.clear, size: 18),
                      label: Text(
                        strings.clear,
                        style: TextStyle(fontFamily: 'Lexend'),
                      ),
                    ),
                  ],
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
                    buildMyLocationMarker(
                      id: 'planner-my-location',
                      position: _myLocation!,
                    ),
                  for (var i = 0; i < _waypoints.length; i++)
                    SchoolWayMapMarker(
                      id: 'planner-pin-$i',
                      latitude: _waypoints[i].latitude,
                      longitude: _waypoints[i].longitude,
                      width:
                          _schoolEndpoint != null && i == _waypoints.length - 1
                          ? 52
                          : 28,
                      height: 38,
                      alignment: Alignment.bottomCenter,
                      child:
                          _schoolEndpoint != null && i == _waypoints.length - 1
                          ? Semantics(
                              label: strings.schoolRouteEndpoint,
                              child: buildRoutePlannerSchoolPinWidget(
                                label: strings.schoolRouteEndpoint,
                              ),
                            )
                          : buildRoutePlannerPinWidget(i + 1),
                    ),
                ],
                polylines: [
                  if (googlePolylinePoints.length >= 2)
                    SchoolWayMapPolyline(
                      id: 'planner-route',
                      points: googlePolylinePoints,
                      strokeWidth: 5,
                      color: SchoolWayTheme.primary,
                    ),
                ],
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => _temporarilyIgnoreMapTaps(),
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
                                _temporarilyIgnoreMapTaps();
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
                                _temporarilyIgnoreMapTaps();
                                _mapController.move(
                                  center:
                                      _mapController.lastRequestedCenter ??
                                      _initialCenter,
                                  zoom: _zoom - 1,
                                );
                              },
                            ),
                            if (_waypoints.length >= 2) ...[
                              Divider(height: 1, thickness: 1),
                              IconButton(
                                tooltip: AppLocalizations.of(context).fitRoute,
                                icon: Icon(
                                  Icons.fit_screen,
                                  color: SchoolWayTheme.primary,
                                ),
                                onPressed: _fitRouteBounds,
                              ),
                            ],
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
                                tooltip: AppLocalizations.of(
                                  context,
                                ).myLocation,
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
              ),
              if (_showStopsPanel && _waypoints.isNotEmpty)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  height: 300,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => _temporarilyIgnoreMapTaps(),
                    child: RouteStopsPanel(
                      stops: List.unmodifiable(_waypoints),
                      onReorder: _reorderWaypoints,
                      onRemove: _removeWaypointAt,
                      onSelect: _centerOnStop,
                      onClose: () => setState(() => _showStopsPanel = false),
                      finalStopIsSchool: _schoolEndpoint != null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Thrown during a split when Google geometry cannot be computed for a part,
/// so the original route is kept instead of losing road-level data.
class RouteGeometryUnavailableException implements Exception {
  const RouteGeometryUnavailableException();

  @override
  String toString() => 'Google geometry unavailable';
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
