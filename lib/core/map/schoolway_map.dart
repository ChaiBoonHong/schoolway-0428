import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/map/feature_gate.dart';
import 'package:schoolway/core/map/schoolway_map_controller.dart';
import 'package:schoolway/core/widgets/osm_map_tile_layer.dart';
import 'package:schoolway/models/models.dart';

/// One map pin. [child] is the rendered content; it is embedded directly on the
/// flutter_map path and rasterized to a bitmap icon on the Google Maps path.
class SchoolWayMapMarker {
  final String id;
  final double latitude;
  final double longitude;
  final Widget child;
  final double width;
  final double height;

  /// flutter_map-style alignment (e.g. [Alignment.bottomCenter]).
  final Alignment alignment;

  const SchoolWayMapMarker({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.child,
    this.width = 48,
    this.height = 58,
    this.alignment = Alignment.bottomCenter,
  });
}

class SchoolWayMapPolyline {
  final String id;
  final List<RouteWaypoint> points;
  final Color color;
  final double strokeWidth;

  const SchoolWayMapPolyline({
    required this.id,
    required this.points,
    required this.color,
    this.strokeWidth = 4,
  });
}

class SchoolWayMapCircle {
  final String id;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;

  const SchoolWayMapCircle({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.fillColor,
    required this.strokeColor,
    this.strokeWidth = 2,
  });
}

/// Dual-provider map surface: Google Maps when [googleEnabled] is true,
/// otherwise the retained OSM/flutter_map implementation. Surfaces pass
/// provider-agnostic markers, polylines, and circles.
class SchoolWayMap extends StatefulWidget {
  final SchoolWayMapController? controller;
  final LatLng initialCenter;
  final double initialZoom;

  /// When null the widget subscribes to [MapFeatureGate] itself. Pass a value
  /// to force a provider for previews or tests.
  final bool? googleEnabled;

  /// When true the Google path is only used if [googleGeometryReady] is also
  /// true. Driver/Parent surfaces set this so Google maps never render for a
  /// route that still lacks valid backend Google geometry.
  final bool requiresGoogleGeometry;

  /// Whether the referenced route has valid (unexpired) Google geometry.
  final bool googleGeometryReady;

  /// Called with a tapped coordinate ([lat], [lng]).
  final void Function(double latitude, double longitude)? onTap;

  /// Called once when the user pans the map away from a programmatic camera.
  final void Function(double latitude, double longitude)? onUserPan;

  /// Called whenever the camera moves (lat, lng, zoom).
  final void Function(double latitude, double longitude, double zoom)?
  onCameraChanged;

  final List<SchoolWayMapMarker> markers;
  final List<SchoolWayMapPolyline> polylines;

  /// Google-route polylines rendered only on the Google Maps path.
  final List<SchoolWayMapPolyline> googlePolylines;

  /// Legacy OSRM/waypoints polylines rendered only on the flutter_map path.
  final List<SchoolWayMapPolyline> legacyPolylines;

  final List<SchoolWayMapCircle> circles;

  /// Shown bottom-left on the flutter_map path only (Google renders its own
  /// attribution).
  final Widget? attribution;

  const SchoolWayMap({
    super.key,
    this.controller,
    required this.initialCenter,
    this.initialZoom = 14,
    this.googleEnabled,
    this.requiresGoogleGeometry = false,
    this.googleGeometryReady = true,
    this.onTap,
    this.onUserPan,
    this.onCameraChanged,
    this.markers = const [],
    this.polylines = const [],
    this.googlePolylines = const [],
    this.legacyPolylines = const [],
    this.circles = const [],
    this.attribution,
  });

  @override
  State<SchoolWayMap> createState() => _SchoolWayMapState();
}

class _SchoolWayMapState extends State<SchoolWayMap> {
  static const double _kMarkerPixelRatio = 3.0;

  final Map<String, google.BitmapDescriptor> _markerIcons = {};
  final Set<String> _pendingRenders = {};
  final Map<String, GlobalKey> _renderKeys = {};
  google.BitmapDescriptor? _defaultMarker;
  StreamSubscription<bool>? _gateSub;
  bool _googleEnabled = false;

  @override
  void initState() {
    super.initState();
    _defaultMarker = google.BitmapDescriptor.defaultMarkerWithHue(
      google.BitmapDescriptor.hueAzure,
    );
    final forced = widget.googleEnabled;
    if (forced != null) {
      _googleEnabled = forced;
    } else {
      unawaited(
        MapFeatureGate.isGoogleMapsEnabled().then((enabled) {
          if (mounted && widget.googleEnabled == null) {
            setState(() => _googleEnabled = enabled);
          }
        }),
      );
      _gateSub = MapFeatureGate.watchGoogleMapsEnabled().listen((enabled) {
        if (mounted && widget.googleEnabled == null) {
          setState(() => _googleEnabled = enabled);
        }
      });
    }
    _scheduleMarkerRenders();
  }

  @override
  void didUpdateWidget(covariant SchoolWayMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.googleEnabled != widget.googleEnabled) {
      final forced = widget.googleEnabled;
      if (forced != null) {
        _gateSub?.cancel();
        _gateSub = null;
        _googleEnabled = forced;
      }
    }
    final newIds = widget.markers.map((m) => m.id).toSet();
    _markerIcons.removeWhere((id, _) => !newIds.contains(id));
    if (widget.markers.any((m) => !_markerIcons.containsKey(m.id))) {
      _scheduleMarkerRenders();
    }
  }

  @override
  void dispose() {
    _gateSub?.cancel();
    super.dispose();
  }

  void _scheduleMarkerRenders() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _renderPendingMarkers();
    });
  }

  void _renderPendingMarkers() {
    if (!mounted) return;
    final missing = widget.markers
        .where((marker) => !_markerIcons.containsKey(marker.id))
        .toList();
    for (final marker in missing) {
      if (_pendingRenders.contains(marker.id)) continue;
      _pendingRenders.add(marker.id);
      final key = _renderKeys.putIfAbsent(marker.id, () => GlobalKey());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _captureMarker(marker, key);
      });
    }
  }

  Future<void> _captureMarker(SchoolWayMapMarker marker, GlobalKey key) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        _pendingRenders.remove(marker.id);
        return;
      }
      final image = await boundary.toImage(pixelRatio: _kMarkerPixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null || !mounted) return;
      final descriptor = google.BitmapDescriptor.bytes(
        byteData.buffer.asUint8List(),
      );
      if (!mounted) return;
      setState(() {
        _markerIcons[marker.id] = descriptor;
        _pendingRenders.remove(marker.id);
      });
    } catch (_) {
      _pendingRenders.remove(marker.id);
    }
  }

  bool get _useGoogle {
    if (!_googleEnabled) return false;
    if (widget.requiresGoogleGeometry && !widget.googleGeometryReady) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final useGoogle = _useGoogle;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (useGoogle) _buildGoogleMap() else _buildFlutterMap(),
        ..._buildOffstageRenderHosts(),
        if (!useGoogle && widget.attribution != null)
          Positioned(
            left: 8,
            bottom: 8,
            child: SafeArea(child: widget.attribution!),
          ),
      ],
    );
  }

  bool _isProgrammaticMove(google.LatLng target) {
    final requested = widget.controller?.lastRequestedCenter;
    if (requested == null) return false;
    const epsilon = 0.00001; // ~1 meter
    return (target.latitude - requested.latitude).abs() < epsilon &&
        (target.longitude - requested.longitude).abs() < epsilon;
  }

  Widget _buildGoogleMap() {
    return google.GoogleMap(
      initialCameraPosition: google.CameraPosition(
        target: google.LatLng(
          widget.initialCenter.latitude,
          widget.initialCenter.longitude,
        ),
        zoom: widget.initialZoom.clamp(3, 19),
      ),
      onMapCreated: (controller) {
        widget.controller?.attachGoogle(controller);
      },
      onTap: widget.onTap == null
          ? null
          : (point) => widget.onTap!(point.latitude, point.longitude),
      onCameraMove: (position) {
        if (widget.onCameraChanged != null) {
          widget.onCameraChanged!(
            position.target.latitude,
            position.target.longitude,
            position.zoom,
          );
        }
        if (widget.onUserPan != null && !_isProgrammaticMove(position.target)) {
          widget.onUserPan!(
            position.target.latitude,
            position.target.longitude,
          );
        }
      },
      myLocationEnabled: false,
      zoomControlsEnabled: false,
      rotateGesturesEnabled: true,
      mapType: google.MapType.normal,
      markers: _googleMarkers(),
      polylines: _googlePolylines(),
      circles: _googleCircles(),
    );
  }

  Set<google.Marker> _googleMarkers() {
    final markers = <google.Marker>{};
    for (final marker in widget.markers) {
      final descriptor = _markerIcons[marker.id] ?? _defaultMarker;
      markers.add(
        google.Marker(
          markerId: google.MarkerId(marker.id),
          position: google.LatLng(marker.latitude, marker.longitude),
          icon: descriptor ?? _defaultMarker!,
          anchor: _googleAnchor(marker.alignment),
          infoWindow: google.InfoWindow.noText,
        ),
      );
    }
    return markers;
  }

  Set<google.Polyline> _googlePolylines() {
    final all = <SchoolWayMapPolyline>[
      ...widget.polylines,
      ...widget.googlePolylines,
    ];
    return all.map((polyline) {
      return google.Polyline(
        polylineId: google.PolylineId(polyline.id),
        points: polyline.points
            .map((w) => google.LatLng(w.latitude, w.longitude))
            .toList(),
        color: polyline.color,
        width: polyline.strokeWidth.round(),
      );
    }).toSet();
  }

  Set<google.Circle> _googleCircles() {
    return widget.circles.map((circle) {
      return google.Circle(
        circleId: google.CircleId(circle.id),
        center: google.LatLng(circle.latitude, circle.longitude),
        radius: circle.radiusMeters,
        fillColor: circle.fillColor,
        strokeColor: circle.strokeColor,
        strokeWidth: circle.strokeWidth.round(),
      );
    }).toSet();
  }

  Offset _googleAnchor(Alignment alignment) {
    return Offset((alignment.x + 1) / 2, (alignment.y + 1) / 2);
  }

  Widget _buildFlutterMap() {
    final controller = widget.controller;
    final flutterController = flutter_map.MapController();
    controller?.attachFlutter(flutterController);
    return flutter_map.FlutterMap(
      mapController: flutterController,
      options: flutter_map.MapOptions(
        initialCenter: widget.initialCenter,
        initialZoom: widget.initialZoom,
        onTap: (tapPosition, latLng) {
          widget.onTap?.call(latLng.latitude, latLng.longitude);
        },
        onPositionChanged: (position, hasGesture) {
          if (widget.onCameraChanged != null) {
            widget.onCameraChanged!.call(
              position.center.latitude,
              position.center.longitude,
              position.zoom,
            );
          }
          if (hasGesture && widget.onUserPan != null) {
            widget.onUserPan!.call(
              position.center.latitude,
              position.center.longitude,
            );
          }
        },
      ),
      children: [
        const OsmMapTileLayer(),
        if (widget.polylines.isNotEmpty || widget.legacyPolylines.isNotEmpty)
          flutter_map.PolylineLayer(
            polylines: [...widget.polylines, ...widget.legacyPolylines].map((
              polyline,
            ) {
              return flutter_map.Polyline(
                points: polyline.points
                    .map((w) => LatLng(w.latitude, w.longitude))
                    .toList(),
                strokeWidth: polyline.strokeWidth,
                color: polyline.color,
              );
            }).toList(),
          ),
        if (widget.circles.isNotEmpty)
          flutter_map.CircleLayer(
            circles: widget.circles.map((circle) {
              return flutter_map.CircleMarker(
                point: LatLng(circle.latitude, circle.longitude),
                radius: circle.radiusMeters,
                useRadiusInMeter: true,
                color: circle.fillColor,
                borderColor: circle.strokeColor,
                borderStrokeWidth: circle.strokeWidth,
              );
            }).toList(),
          ),
        if (widget.markers.isNotEmpty)
          flutter_map.MarkerLayer(
            markers: widget.markers.map((marker) {
              return flutter_map.Marker(
                point: LatLng(marker.latitude, marker.longitude),
                width: marker.width,
                height: marker.height,
                alignment: marker.alignment,
                child: marker.child,
              );
            }).toList(),
          ),
      ],
    );
  }

  List<Widget> _buildOffstageRenderHosts() {
    if (widget.markers.isEmpty) return const [];
    final hosts = <Widget>[];
    for (final marker in widget.markers) {
      if (_markerIcons.containsKey(marker.id)) continue;
      final key = _renderKeys.putIfAbsent(marker.id, () => GlobalKey());
      hosts.add(
        Positioned(
          left: -10000,
          top: -10000,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: marker.width,
              height: marker.height,
              child: marker.child,
            ),
          ),
        ),
      );
    }
    return hosts;
  }
}
