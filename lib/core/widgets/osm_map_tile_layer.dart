import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../config.dart';
import '../map_tile_http_client.dart';
import '../../services/map_tile_config_service.dart';

/// Network tile layer with URL from Firestore when configured, else [AppConfig] default.
class OsmMapTileLayer extends StatelessWidget {
  const OsmMapTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: MapTileConfigService.tileUrlTemplateStream(),
      builder: (context, snapshot) {
        final url = snapshot.hasError
            ? AppConfig.defaultMapTileUrlTemplate
            : (snapshot.data ?? AppConfig.defaultMapTileUrlTemplate);
        return TileLayer(
          urlTemplate: url,
          userAgentPackageName: 'com.schoolway.app',
          // Web: aborting superseded tile requests triggers DomException
          // "AbortError" (browser fetch cancel) and spams the console; mobile
          // keeps aborts for bandwidth. See flutter_map NetworkTileProvider.
          tileProvider: NetworkTileProvider(
            httpClient: mapTileHttpClient,
            abortObsoleteRequests: !kIsWeb,
          ),
        );
      },
    );
  }
}
