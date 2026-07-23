import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/firebase_service.dart';

/// Detects if the bus is stationary for an unusually long time and fires an emergency alert.
class StationaryBusDetector {
  static final StationaryBusDetector _instance = StationaryBusDetector._internal();
  factory StationaryBusDetector() => _instance;
  StationaryBusDetector._internal();

  Timer? _checkTimer;
  GpsTracking? _lastGps;
  DateTime? _stationarySince;
  
  String? _activeBusId;
  String? _activeSessionId;
  
  bool _isRunning = false;
  
  // Configurable thresholds
  final Duration _stationaryThreshold = const Duration(minutes: 8);
  
  void start({required String busId, required String sessionId}) {
    if (_isRunning && _activeSessionId == sessionId) return;
    
    stop();
    _activeBusId = busId;
    _activeSessionId = sessionId;
    _isRunning = true;
    _stationarySince = null;
    _lastGps = null;
    
    // Check every minute
    _checkTimer = Timer.periodic(const Duration(minutes: 1), _checkStationary);
  }
  
  void stop() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _isRunning = false;
    _stationarySince = null;
    _lastGps = null;
    _activeBusId = null;
    _activeSessionId = null;
  }
  
  void updateGps(GpsTracking gps) {
    if (!_isRunning) return;
    
    if (_lastGps == null) {
      _lastGps = gps;
      _stationarySince = DateTime.now();
      return;
    }
    
    // If speed > 2 km/h, we are moving.
    if (gps.speed > 2.0) {
      _stationarySince = DateTime.now(); // reset
      _lastGps = gps;
      return;
    }
  }
  
  void _checkStationary(Timer timer) async {
    if (!_isRunning || _stationarySince == null || _activeBusId == null || _lastGps == null) return;
    
    final now = DateTime.now();
    final stationaryDuration = now.difference(_stationarySince!);
    
    if (stationaryDuration >= _stationaryThreshold) {
      // Fire emergency alert
      debugPrint("Bus is stationary for too long! Firing auto-alert.");
      
      try {
        await FirebaseService.createEmergencyAlert(
          driverId: FirebaseService.currentUserId ?? 'unknown_driver',
          busId: _activeBusId!,
          sessionId: _activeSessionId,
          latitude: _lastGps!.latitude,
          longitude: _lastGps!.longitude,
        );
        // Reset to avoid spamming
        _stationarySince = now;
      } catch (e) {
        debugPrint("Failed to create auto-alert: $e");
      }
    }
  }
}
