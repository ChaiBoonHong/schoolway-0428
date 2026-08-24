import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/config.dart';
import '../core/schoolway_firestore.dart';
import '../models/models.dart';
import 'firebase_service.dart';
import 'location_service.dart';

/// Periodically uploads the device position to [gps_tracking] for the active bus.
class DriverGpsUploader {
  Timer? _timer;
  String? _busId;
  String? _sessionId;

  Future<void> start({required String busId, String? sessionId}) async {
    if (_busId == busId && _sessionId == sessionId && _timer != null) {
      return;
    }
    await stop();
    _busId = busId;
    _sessionId = sessionId;

    final ok = await LocationService.ensureLocationPermission();
    if (!ok) {
      debugPrint('DriverGpsUploader: location permission not granted');
      return;
    }

    await _uploadOnce();
    _timer = Timer.periodic(AppConfig.gpsUploadInterval, (_) => _uploadOnce());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _busId = null;
    _sessionId = null;
  }

  Future<void> _uploadOnce() async {
    final busId = _busId;
    if (busId == null) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final speedKmh = pos.speed * 3.6;
      final acc = pos.accuracy;
      final tracking = GpsTracking(
        busId: busId,
        latitude: pos.latitude,
        longitude: pos.longitude,
        speed: speedKmh.isFinite ? speedKmh.clamp(0.0, 400.0) : 0.0,
        heading: pos.heading.isFinite ? pos.heading : 0.0,
        accuracy: acc.isFinite && acc >= 0 ? acc : 0.0,
        timestamp: DateTime.now(),
        sessionId: _sessionId,
      );
      await FirebaseService.updateGpsLocation(tracking);

      final sessionId = _sessionId;
      if (sessionId != null && sessionId.isNotEmpty) {
        await swFirestore
            .collection('route_sessions')
            .doc(sessionId)
            .collection('breadcrumbs')
            .add(tracking.toFirestore());
      }
    } catch (e) {
      debugPrint('DriverGpsUploader: upload failed: $e');
    }
  }
}
