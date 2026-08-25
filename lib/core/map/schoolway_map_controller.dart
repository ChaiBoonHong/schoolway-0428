import 'dart:async';

import 'package:google_maps_flutter/google_maps_flutter.dart' as google;
import 'package:latlong2/latlong.dart';

/// Adapter controller for the Google Maps controller.
/// Moves requested before the map is attached are buffered and replayed.
class SchoolWayMapController {
  google.GoogleMapController? _googleController;

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

  Future<void> move({required LatLng center, required double zoom}) async {
    if (_disposed) return;
    lastRequestedCenter = center;
    final gc = _googleController;
    if (gc != null) {
      await gc.moveCamera(
        google.CameraUpdate.newLatLngZoom(
          google.LatLng(center.latitude, center.longitude),
          zoom.clamp(3, 19),
        ),
      );
      return;
    }
    _pendingCenter = center;
    _pendingZoom = zoom;
  }

  Future<void> animate({required LatLng center, required double zoom}) async {
    if (_disposed) return;
    lastRequestedCenter = center;
    final gc = _googleController;
    if (gc != null) {
      await gc.animateCamera(
        google.CameraUpdate.newLatLngZoom(
          google.LatLng(center.latitude, center.longitude),
          zoom.clamp(3, 19),
        ),
      );
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
    lastRequestedCenter = LatLng(
      (southLatitude + northLatitude) / 2,
      (westLongitude + eastLongitude) / 2,
    );
    final gc = _googleController;
    if (gc != null) {
      await gc.moveCamera(
        google.CameraUpdate.newLatLngBounds(
          google.LatLngBounds(
            southwest: google.LatLng(southLatitude, westLongitude),
            northeast: google.LatLng(northLatitude, eastLongitude),
          ),
          padding,
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
    }
  }

  void dispose() {
    _disposed = true;
    _googleController?.dispose();
    _googleController = null;
  }
}
