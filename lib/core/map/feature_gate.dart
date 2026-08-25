import 'dart:async';

import 'package:schoolway/core/schoolway_firestore.dart';

import '../config.dart';

/// Provider-level feature gate that keeps the OSM/flutter_map implementation
/// live until Google map surfaces have been verified and production traffic is
/// cut over.
///
/// Enabled by setting `googleMapsEnabled: true` on `app_config/map`
/// ([AppConfig.mapTileFirestoreDocPath]). Defaults to false so nothing renders
/// Google content before the operator approves the migration.
abstract final class MapFeatureGate {
  static bool _cachedValue = false;

  /// Current known value (updated by [watch]).
  static bool get googleMapsEnabled => _cachedValue;

  /// One-shot check.
  static Future<bool> isGoogleMapsEnabled() async {
    try {
      final snap = await swFirestore
          .doc(AppConfig.mapTileFirestoreDocPath)
          .get();
      final value = (snap.data()?['googleMapsEnabled'] as bool?) ?? false;
      _cachedValue = value;
      return value;
    } catch (_) {
      return false;
    }
  }

  /// Live stream of the flag. Keep one subscription per map host screen.
  static Stream<bool> watchGoogleMapsEnabled() async* {
    await isGoogleMapsEnabled();
    yield _cachedValue;
    yield* swFirestore.doc(AppConfig.mapTileFirestoreDocPath).snapshots().map((
      snap,
    ) {
      final value = (snap.data()?['googleMapsEnabled'] as bool?) ?? false;
      _cachedValue = value;
      return value;
    });
  }
}
