import 'package:http/http.dart';
import 'package:http/retry.dart';

/// Single [Client] for map tiles so connections can be reused. Over HTTPS,
/// the platform stack typically negotiates HTTP/2 when the tile host supports it.
final Client mapTileHttpClient = RetryClient(Client());
