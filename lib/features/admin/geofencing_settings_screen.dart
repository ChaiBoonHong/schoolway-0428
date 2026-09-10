import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/map/map_markers.dart';
import 'package:schoolway/core/map/schoolway_map.dart';
import 'package:schoolway/core/map/schoolway_map_controller.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/services/school_config_service.dart';
import 'package:schoolway/services/location_service.dart';

class GeofencingSettingsScreen extends StatefulWidget {
  const GeofencingSettingsScreen({super.key});

  @override
  State<GeofencingSettingsScreen> createState() =>
      _GeofencingSettingsScreenState();
}

class _GeofencingSettingsScreenState extends State<GeofencingSettingsScreen> {
  static const _fallbackCenter = LatLng(3.1390, 101.6869);

  final SchoolWayMapController _mapController = SchoolWayMapController();

  bool _loading = true;
  bool _saving = false;
  bool _locating = false;
  bool _enabled = false;
  LatLng? _center;
  double _schoolRadius = 250;
  double _routeCorridor = 300;
  double _zoom = 15;
  LatLng _cameraCenter = _fallbackCenter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await SchoolConfigService.getGeofenceConfig();
    if (!mounted) return;
    setState(() {
      _enabled = config.enabled;
      _center = config.center;
      _schoolRadius = config.schoolRadiusMeters;
      _routeCorridor = config.routeCorridorMeters;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final strings = AppLocalizations.of(context);
    if (_enabled && _center == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.selectSchoolAreaOnMap)));
      return;
    }
    setState(() => _saving = true);
    try {
      await SchoolConfigService.saveGeofenceConfig(
        SchoolGeofenceConfig(
          enabled: _enabled,
          latitude: _center?.latitude,
          longitude: _center?.longitude,
          schoolRadiusMeters: _schoolRadius,
          routeCorridorMeters: _routeCorridor,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.geofenceSettingsSaved)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _locateMe() async {
    if (_locating) return;
    setState(() => _locating = true);
    final position = await LocationService.getCurrentPositionBestEffort();
    if (!mounted) return;
    setState(() => _locating = false);
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).unableToGetCurrentLocation,
          ),
        ),
      );
      return;
    }
    final location = LatLng(position.latitude, position.longitude);
    setState(() {
      _center = location;
      _cameraCenter = location;
      _zoom = 17;
    });
    await _mapController.animate(center: location, zoom: 17);
  }

  void _zoomBy(double delta) {
    final nextZoom = (_zoom + delta).clamp(3.0, 19.0);
    _zoom = nextZoom;
    _mapController.move(center: _cameraCenter, zoom: nextZoom);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final center = _center ?? _fallbackCenter;
    return Scaffold(
      appBar: AppBar(title: Text(strings.geofencingSettings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.enableGeofencing),
            subtitle: Text(strings.geofencingDescription),
            value: _enabled,
            onChanged: (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: 12),
          Semantics(
            label: strings.selectSchoolAreaOnMap,
            child: SizedBox(
              height: 360,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    SchoolWayMap(
                      controller: _mapController,
                      initialCenter: center,
                      initialZoom: 15,
                      eagerGestureHandling: true,
                      onCameraChanged: (latitude, longitude, zoom) {
                        _cameraCenter = LatLng(latitude, longitude);
                        _zoom = zoom;
                      },
                      onTap: (latitude, longitude) =>
                          setState(() => _center = LatLng(latitude, longitude)),
                      markers: [
                        if (_center != null)
                          SchoolWayMapMarker(
                            id: 'school-geofence-center',
                            latitude: _center!.latitude,
                            longitude: _center!.longitude,
                            child: buildStopNumberWidget(number: 1),
                          ),
                      ],
                      circles: [
                        if (_center != null)
                          SchoolWayMapCircle(
                            id: 'school-geofence',
                            latitude: _center!.latitude,
                            longitude: _center!.longitude,
                            radiusMeters: _schoolRadius,
                            fillColor: SchoolWayTheme.accent.withValues(
                              alpha: 0.18,
                            ),
                            strokeColor: SchoolWayTheme.accent,
                          ),
                      ],
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _GeofenceMapControl(
                            icon: Icons.add,
                            tooltip: strings.zoomIn,
                            onPressed: () => _zoomBy(1),
                          ),
                          const SizedBox(height: 8),
                          _GeofenceMapControl(
                            icon: Icons.remove,
                            tooltip: strings.zoomOut,
                            onPressed: () => _zoomBy(-1),
                          ),
                          const SizedBox(height: 8),
                          _GeofenceMapControl(
                            icon: Icons.my_location,
                            tooltip: strings.locateMe,
                            onPressed: _locating ? null : _locateMe,
                            loading: _locating,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(strings.schoolAreaRadius(_schoolRadius.round())),
          Slider(
            value: _schoolRadius.clamp(
              SchoolGeofenceConfig.minimumDistanceMeters,
              SchoolGeofenceConfig.maximumDistanceMeters,
            ),
            min: SchoolGeofenceConfig.minimumDistanceMeters,
            max: SchoolGeofenceConfig.maximumDistanceMeters,
            divisions: 99,
            label: '${_schoolRadius.round()} m',
            onChanged: (value) => setState(() => _schoolRadius = value),
          ),
          Text(strings.routeCorridorDistance(_routeCorridor.round())),
          Slider(
            value: _routeCorridor.clamp(
              SchoolGeofenceConfig.minimumDistanceMeters,
              SchoolGeofenceConfig.maximumDistanceMeters,
            ),
            min: SchoolGeofenceConfig.minimumDistanceMeters,
            max: SchoolGeofenceConfig.maximumDistanceMeters,
            divisions: 99,
            label: '${_routeCorridor.round()} m',
            onChanged: (value) => setState(() => _routeCorridor = value),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(strings.saveGeofenceSettings),
          ),
        ],
      ),
    );
  }
}

class _GeofenceMapControl extends StatelessWidget {
  const _GeofenceMapControl({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.loading = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SchoolWayTheme.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox.square(
        dimension: 48,
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(13),
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : IconButton(
                tooltip: tooltip,
                onPressed: onPressed,
                icon: Icon(icon, color: SchoolWayTheme.primary),
              ),
      ),
    );
  }
}
