import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/map/schoolway_map_controller.dart';
import 'package:schoolway/models/models.dart';

class SchoolWayMapMarker {
  final String id;
  final double latitude;
  final double longitude;
  final Widget child;
  final double width;
  final double height;
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

/// Google Maps map surface. All markers, polylines, circles are rendered via
/// Google Maps for Flutter.
class SchoolWayMap extends StatefulWidget {
  final SchoolWayMapController? controller;
  final LatLng initialCenter;
  final double initialZoom;
  final void Function(double latitude, double longitude)? onTap;
  final void Function(double latitude, double longitude)? onUserPan;
  final void Function(double latitude, double longitude, double zoom)?
  onCameraChanged;
  final List<SchoolWayMapMarker> markers;
  final List<SchoolWayMapPolyline> polylines;
  final List<SchoolWayMapCircle> circles;

  const SchoolWayMap({
    super.key,
    this.controller,
    required this.initialCenter,
    this.initialZoom = 14,
    this.onTap,
    this.onUserPan,
    this.onCameraChanged,
    this.markers = const [],
    this.polylines = const [],
    this.circles = const [],
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

  @override
  void initState() {
    super.initState();
    _defaultMarker = google.BitmapDescriptor.defaultMarkerWithHue(
      google.BitmapDescriptor.hueAzure,
    );
    _scheduleMarkerRenders();
  }

  @override
  void didUpdateWidget(covariant SchoolWayMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newIds = widget.markers.map((m) => m.id).toSet();
    _markerIcons.removeWhere((id, _) => !newIds.contains(id));
    if (widget.markers.any((m) => !_markerIcons.containsKey(m.id))) {
      _scheduleMarkerRenders();
    }
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
      final ratio = kIsWeb ? 1.0 : _kMarkerPixelRatio;
      final image = await boundary.toImage(pixelRatio: ratio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null || !mounted) return;
      final descriptor = google.BitmapDescriptor.bytes(
        byteData.buffer.asUint8List(),
        imagePixelRatio: ratio,
        width: marker.width,
        height: marker.height,
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [_buildGoogleMap(), ..._buildOffstageRenderHosts()],
    );
  }

  bool _isProgrammaticMove(google.LatLng target) {
    final requested = widget.controller?.lastRequestedCenter;
    if (requested == null) return false;
    const epsilon = 0.00001;
    return (target.latitude - requested.latitude).abs() < epsilon &&
        (target.longitude - requested.longitude).abs() < epsilon;
  }

  /// Map style that hides POIs (businesses, shops, restaurants, attractions)
  /// and transit stations to produce a clean, uncluttered map.
  static const String _cleanMapStyle = '''
[
  {
    "featureType": "poi",
    "elementType": "all",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  },
  {
    "featureType": "transit.station",
    "elementType": "all",
    "stylers": [
      {
        "visibility": "off"
      }
    ]
  }
]
''';

  Widget _buildGoogleMap() {
    return google.GoogleMap(
      style: _cleanMapStyle,
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
    return widget.polylines.map((polyline) {
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
