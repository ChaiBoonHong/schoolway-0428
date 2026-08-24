import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';

/// Warns at seven minutes and sends one alert after eight minutes without
/// meaningful movement. A new episode starts only after movement resumes.
class StationaryBusDetector {
  static final StationaryBusDetector _instance =
      StationaryBusDetector._internal();
  factory StationaryBusDetector() => _instance;
  StationaryBusDetector._internal()
    : warningThreshold = const Duration(minutes: 7),
      alertThreshold = const Duration(minutes: 8),
      staleGpsThreshold = const Duration(seconds: 30),
      checkInterval = const Duration(seconds: 15),
      stationaryRadiusMeters = 30,
      movingSpeedKmh = 2,
      _alertHandler = null;

  @visibleForTesting
  StationaryBusDetector.testing({
    required this.warningThreshold,
    required this.alertThreshold,
    required this.staleGpsThreshold,
    required this.checkInterval,
    this.stationaryRadiusMeters = 30,
    this.movingSpeedKmh = 2,
    Future<void> Function(GpsTracking gps)? alertHandler,
  }) : _alertHandler = alertHandler;

  final Duration warningThreshold;
  final Duration alertThreshold;
  final Duration staleGpsThreshold;
  final Duration checkInterval;
  final double stationaryRadiusMeters;
  final double movingSpeedKmh;
  final Future<void> Function(GpsTracking gps)? _alertHandler;

  Timer? _checkTimer;
  GpsTracking? _lastGps;
  GpsTracking? _anchorGps;
  DateTime? _stationarySince;
  String? _activeBusId;
  String? _activeSessionId;
  VoidCallback? _onWarning;
  bool _isRunning = false;
  bool _warningShown = false;
  bool _alertSent = false;

  void start({
    required String busId,
    required String sessionId,
    VoidCallback? onWarning,
  }) {
    if (_isRunning && _activeSessionId == sessionId) {
      _onWarning = onWarning;
      return;
    }
    stop();
    _activeBusId = busId;
    _activeSessionId = sessionId;
    _onWarning = onWarning;
    _isRunning = true;
    _checkTimer = Timer.periodic(checkInterval, _checkStationary);
  }

  void stop() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _isRunning = false;
    _lastGps = null;
    _anchorGps = null;
    _stationarySince = null;
    _activeBusId = null;
    _activeSessionId = null;
    _onWarning = null;
    _warningShown = false;
    _alertSent = false;
  }

  void updateGps(GpsTracking gps) {
    if (!_isRunning) return;
    _lastGps = gps;

    if (gps.speed > movingSpeedKmh) {
      _resetEpisode();
      return;
    }

    final anchor = _anchorGps;
    if (anchor == null) {
      _beginEpisode(gps);
      return;
    }

    final distance = Geolocator.distanceBetween(
      anchor.latitude,
      anchor.longitude,
      gps.latitude,
      gps.longitude,
    );
    if (distance > stationaryRadiusMeters) _beginEpisode(gps);
  }

  void _beginEpisode(GpsTracking gps) {
    _anchorGps = gps;
    _stationarySince = DateTime.now();
    _warningShown = false;
    _alertSent = false;
  }

  void _resetEpisode() {
    _anchorGps = null;
    _stationarySince = null;
    _warningShown = false;
    _alertSent = false;
  }

  Future<void> _checkStationary(Timer _) async {
    final gps = _lastGps;
    final since = _stationarySince;
    final busId = _activeBusId;
    if (!_isRunning || gps == null || since == null || busId == null) return;

    final now = DateTime.now();
    final gpsAge = now.difference(gps.timestamp);
    if (gpsAge > staleGpsThreshold) return;

    final duration = now.difference(since);
    if (!_warningShown && duration >= warningThreshold) {
      _warningShown = true;
      _onWarning?.call();
    }
    if (_alertSent || duration < alertThreshold) return;

    _alertSent = true;
    try {
      final handler = _alertHandler;
      if (handler != null) {
        await handler(gps);
      } else {
        await FirebaseService.createEmergencyAlert(
          driverUid: FirebaseService.currentUserId ?? 'unknown_driver',
          busId: busId,
          sessionId: _activeSessionId,
          latitude: gps.latitude,
          longitude: gps.longitude,
        );
      }
    } catch (e) {
      _alertSent = false;
      debugPrint('Failed to create automatic stationary alert: $e');
    }
  }
}
