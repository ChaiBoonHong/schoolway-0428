import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Location permission + one-shot position reads (driver, emergency, etc.).
class LocationService {
  LocationService._();

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
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
