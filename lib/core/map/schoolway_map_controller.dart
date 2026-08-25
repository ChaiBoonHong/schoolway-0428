import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'package:latlong2/latlong.dart';

/// Adapter controller that drives either a [google.GoogleMapController] or a
/// [flutter_map.MapController] so existing call sites keep the same API.
///
/// Moves requested before the platform map is attached are buffered and
/// replayed once the controller becomes available.
class SchoolWayMapController {
  google.GoogleMapController? _googleController;
  flutter_map.MapController? _flutterController;

  bool _disposed = false;
  LatLng? _pendingCenter;
  double? _pendingZoom;

  /// Last center requested via [move]/[animate]; used to tell programmatic
  /// camera moves apart from user gestures.
  LatLng? lastRequestedCenter;

  void attachGoogle(google.GoogleMapController controller) {
    _googleController = controller;
    _flushPending();
  }

  void attachFlutter(flutter_map.MapController controller) {
    _flutterController = controller;
    _flushPending();
  }

  Future<void> move({required LatLng center, required double zoom}) async {
    if (_disposed) return;
    lastRequestedCenter = center;
    final googleController = _googleController;
    if (googleController != null) {
      await googleController.moveCamera(
        google.CameraUpdate.newLatLngZoom(
          google.LatLng(center.latitude, center.longitude),
          zoom.clamp(3, 19),
        ),
      );
      return;
    }
    final flutterController = _flutterController;
    if (flutterController != null) {
      flutterController.move(center, zoom.clamp(3, 19));
      return;
    }
    _pendingCenter = center;
    _pendingZoom = zoom;
  }

  Future<void> animate({required LatLng center, required double zoom}) async {
    if (_disposed) return;
    lastRequestedCenter = center;
    final googleController = _googleController;
    if (googleController != null) {
      await googleController.animateCamera(
        google.CameraUpdate.newLatLngZoom(
          google.LatLng(center.latitude, center.longitude),
          zoom.clamp(3, 19),
        ),
      );
      return;
    }
    final flutterController = _flutterController;
    if (flutterController != null) {
      flutterController.move(center, zoom.clamp(3, 19));
      return;
    }
    _pendingCenter = center;
    _pendingZoom = zoom;
  }

  Future<void> fitBounds({
    required double southLatitude,
    required double westLongitude,
    required double northLatitude,
    required double eastLongitude,
    double padding = 56,
    double maxZoom = 17,
  }) async {
    if (_disposed) return;
    final southWest = LatLng(southLatitude, westLongitude);
    final northEast = LatLng(northLatitude, eastLongitude);
    lastRequestedCenter = LatLng(
      (southLatitude + northLatitude) / 2,
      (westLongitude + eastLongitude) / 2,
    );
    final googleController = _googleController;
    if (googleController != null) {
      await googleController.moveCamera(
        google.CameraUpdate.newLatLngBounds(
          google.LatLngBounds(
            southwest: google.LatLng(southWest.latitude, southWest.longitude),
            northeast: google.LatLng(northEast.latitude, northEast.longitude),
          ),
          padding,
        ),
      );
      return;
    }
    final flutterController = _flutterController;
    if (flutterController != null) {
      flutterController.fitCamera(
        flutter_map.CameraFit.bounds(
          bounds: flutter_map.LatLngBounds(southWest, northEast),
          padding: EdgeInsets.all(padding),
          maxZoom: maxZoom,
        ),
      );
      return;
    }
    _pendingCenter = lastRequestedCenter;
    _pendingZoom = 14;
  }

  void _flushPending() {
    final center = _pendingCenter;
    final zoom = _pendingZoom;
    if (center == null || zoom == null) return;
    _pendingCenter = null;
    _pendingZoom = null;
    if (_googleController != null) {
      unawaited(move(center: center, zoom: zoom));
      return;
    }
    final flutterController = _flutterController;
    if (flutterController != null) {
      // The FlutterMap widget may not be laid out yet during build; replay
      // after the current frame so the controller is attached.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed || _flutterController != flutterController) return;
        flutterController.move(center, zoom.clamp(3, 19));
      });
      return;
    }
    _pendingCenter = center;
    _pendingZoom = zoom;
  }

  void dispose() {
    _disposed = true;
    _googleController?.dispose();
    _googleController = null;
    _flutterController = null;
  }
}
