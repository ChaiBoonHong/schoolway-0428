import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:schoolway/core/schoolway_firestore.dart';

import '../core/config.dart';

/// Remote map tile template from Firestore (`app_config/map`), so operators can
/// change the endpoint without shipping a new app build.
class MapTileConfigService {
  MapTileConfigService._();

  static final FirebaseFirestore _db = swFirestore;

  /// Document: [AppConfig.mapTileFirestoreDocPath]
  static Stream<String> tileUrlTemplateStream() {
    return _db.doc(AppConfig.mapTileFirestoreDocPath).snapshots().map((snap) {
      final raw = snap.data()?['tileUrlTemplate'] as String?;
      final resolved = _validateTileUrlTemplate(raw);
      return resolved ?? AppConfig.defaultMapTileUrlTemplate;
    });
  }

  static String? _validateTileUrlTemplate(String? url) {
    if (url == null) return null;
    final t = url.trim();
    if (t.isEmpty) return null;
    if (!t.contains('{z}') || !t.contains('{x}') || !t.contains('{y}')) {
      return null;
    }
    final lower = t.toLowerCase();
    if (!lower.startsWith('https://')) return null;
    return t;
  }
}
