import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Location permission + one-shot position reads (driver, emergency, etc.).
class LocationService {
  LocationService._();

  static Position? _latestPosition;

  @visibleForTesting
  static void clearRememberedPosition() {
    _latestPosition = null;
  }

  static void rememberPosition(Position position) {
    final latest = _latestPosition;
    if (latest == null || !position.timestamp.isBefore(latest.timestamp)) {
      _latestPosition = position;
    }
  }

  static Position? recentPosition({
    DateTime? now,
    Duration maxAge = const Duration(minutes: 15),
  }) {
    final position = _latestPosition;
    if (position == null) return null;
    final age = (now ?? DateTime.now()).difference(position.timestamp).abs();
    return age <= maxAge ? position : null;
  }

  static Future<bool> ensureLocationPermission() async {
    if (kIsWeb) {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.deniedForever) {
        return false;
      }
      return p == LocationPermission.whileInUse ||
          p == LocationPermission.always;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Returns null if permission denied or position unavailable.
  static Future<Position?> getCurrentPositionBestEffort() async {
    final ok = await ensureLocationPermission();
    if (!ok) return null;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      rememberPosition(position);
      return position;
    } catch (_) {
      return recentPosition();
    }
  }
}
