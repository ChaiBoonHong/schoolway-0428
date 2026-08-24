import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/config.dart';
import '../core/diagnostics/app_logger.dart';
import '../core/schoolway_firestore.dart';
import '../models/models.dart';
import 'firebase_service.dart';
import 'location_service.dart';

/// Periodically uploads the device position to [gps_tracking] for the active bus.
class DriverGpsUploader {
  Timer? _timer;
  String? _busId;
  String? _sessionId;
  bool _uploadInProgress = false;
  int _generation = 0;
  DateTime? _lastUploadedAt;

  Future<void> start({required String busId, String? sessionId}) async {
    if (_busId == busId && _sessionId == sessionId && _timer != null) {
      return;
    }
    await stop();
    _busId = busId;
    _sessionId = sessionId;

    final ok = await LocationService.ensureLocationPermission();
    if (!ok) {
      AppLogger.info('location', 'Location upload was not started.');
      return;
    }

    await _uploadOnce();
    _timer = Timer.periodic(AppConfig.gpsUploadInterval, (_) => _uploadOnce());
  }

  Future<void> stop() async {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _busId = null;
    _sessionId = null;
    _lastUploadedAt = null;
  }

  Future<void> _uploadOnce() async {
    final busId = _busId;
    final sessionId = _sessionId;
    final generation = _generation;
    final driverUid = FirebaseAuth.instance.currentUser?.uid;
    if (busId == null || driverUid == null || _uploadInProgress) return;
    _uploadInProgress = true;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final speedKmh = pos.speed * 3.6;
      final acc = pos.accuracy;
      if (generation != _generation ||
          busId != _busId ||
          sessionId != _sessionId) {
        return;
      }
      final capturedAt = pos.timestamp;
      if (_lastUploadedAt != null && !capturedAt.isAfter(_lastUploadedAt!)) {
        return;
      }
      final tracking = GpsTracking(
        busId: busId,
        latitude: pos.latitude,
        longitude: pos.longitude,
        speed: speedKmh.isFinite ? speedKmh.clamp(0.0, 400.0) : 0.0,
        heading: pos.heading.isFinite ? pos.heading : 0.0,
        accuracy: acc.isFinite && acc >= 0 ? acc : 0.0,
        timestamp: capturedAt,
        sessionId: sessionId,
        driverUid: driverUid,
      );
      await FirebaseService.updateGpsLocation(tracking);
      _lastUploadedAt = capturedAt;

      if (sessionId != null && sessionId.isNotEmpty) {
        await swFirestore
            .collection('route_sessions')
            .doc(sessionId)
            .collection('breadcrumbs')
            .add(tracking.toFirestore());
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'location',
        'A location update could not be uploaded.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _uploadInProgress = false;
    }
  }
}
