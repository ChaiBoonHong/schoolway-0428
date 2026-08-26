import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/models/models.dart';

void main() {
  group('decodeEncodedPolyline', () {
    test('decodes a known encoded polyline', () {
      final points = decodeEncodedPolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(points.length, 3);
      expect(points[0].latitude, closeTo(38.5, 0.01));
      expect(points[0].longitude, closeTo(-120.2, 0.01));
    });

    test('returns empty for empty input', () {
      expect(decodeEncodedPolyline(''), isEmpty);
    });

    test('round-trips a simple line', () {
      final encoded = encodeTestPolyline([
        [3.1, 101.7],
        [3.2, 101.8],
        [3.3, 101.9],
      ]);
      final decoded = decodeEncodedPolyline(encoded);
      expect(decoded.length, 3);
      expect(decoded[0].latitude, closeTo(3.1, 1e-4));
      expect(decoded[2].longitude, closeTo(101.9, 1e-4));
    });
  });

  group('encodeEncodedPolyline', () {
    test('encodes route waypoints and round-trips correctly', () {
      final waypoints = [
        RouteWaypoint(latitude: 3.12345, longitude: 101.65432),
        RouteWaypoint(latitude: 3.23456, longitude: 101.76543),
        RouteWaypoint(latitude: 3.34567, longitude: 101.87654),
      ];
      final encoded = encodeEncodedPolyline(waypoints);
      expect(encoded, isNotEmpty);
      final decoded = decodeEncodedPolyline(encoded);
      expect(decoded.length, 3);
      expect(decoded[0].latitude, closeTo(3.12345, 1e-5));
      expect(decoded[0].longitude, closeTo(101.65432, 1e-5));
      expect(decoded[1].latitude, closeTo(3.23456, 1e-5));
      expect(decoded[1].longitude, closeTo(101.76543, 1e-5));
      expect(decoded[2].latitude, closeTo(3.34567, 1e-5));
      expect(decoded[2].longitude, closeTo(101.87654, 1e-5));
    });

    test('returns empty for empty list', () {
      expect(encodeEncodedPolyline(const []), isEmpty);
    });
  });

  group('GoogleRouteGeometry', () {
    test('parses from a map and reports expiry', () {
      final now = DateTime.now();
      final geometry = GoogleRouteGeometry(
        encodedPolyline: '_p~iF~ps|U',
        distanceMeters: 5000,
        durationSeconds: 300,
        stopHash: 'abc123',
        generatedAt: now,
        expiresAt: now.add(const Duration(days: 29)),
      );
      final map = geometry.toMap();
      final parsed = GoogleRouteGeometry.fromMap(map);
      expect(parsed.encodedPolyline, '_p~iF~ps|U');
      expect(parsed.stopHash, 'abc123');
      expect(parsed.isExpired, isFalse);
    });

    test('decodeWaypoints yields ordered points', () {
      final encoded = encodeTestPolyline([
        [3.1, 101.7],
        [3.2, 101.8],
      ]);
      final geometry = GoogleRouteGeometry(
        encodedPolyline: encoded,
        stopHash: 'h',
        generatedAt: DateTime.utc(2026),
        expiresAt: DateTime.utc(2027),
      );
      expect(geometry.decodeWaypoints().length, 2);
    });
  });

  group('TrafficEtaSnapshot', () {
    test('parses an ok callable response', () {
      final snapshot = TrafficEtaSnapshot.fromCallable({
        'sessionId': 's1',
        'routeId': 'r1',
        'busId': 'b1',
        'reason': 'ok',
        'cached': true,
        'stale': false,
        'polyline': encodeTestPolyline([
          [3.1, 101.7],
          [3.2, 101.8],
        ]),
        'distanceMeters': 1234,
        'durationSeconds': 360,
        'tripDirection': 'fromSchool',
        'stopEtas': [
          {
            'stopIndex': 0,
            'routeStopIndex': 2,
            'label': 'Stop 1',
            'etaMinutes': 5,
          },
        ],
      });
      expect(snapshot.isOk, isTrue);
      expect(snapshot.isAvailable, isTrue);
      expect(snapshot.tripDirection, TripDirection.fromSchool);
      expect(snapshot.stopEtas.single.routeStopIndex, 2);
      expect(snapshot.decodeWaypoints().length, 2);
    });

    test('maps lifecycle reasons', () {
      expect(
        TrafficEtaSnapshot.fromCallable({'reason': 'stale-gps'}).reason,
        TrafficEtaReason.staleGps,
      );
      expect(
        TrafficEtaSnapshot.fromCallable({
          'reason': 'all-stops-completed',
        }).reason,
        TrafficEtaReason.allStopsCompleted,
      );
      expect(
        TrafficEtaSnapshot.fromCallable({'reason': 'bogus'}).reason,
        TrafficEtaReason.unknown,
      );
    });

    test('isExpired respects expiresAt', () {
      final fresh = TrafficEtaSnapshot.fromCallable({
        'reason': 'ok',
        'expiresAt': DateTime.now().add(const Duration(minutes: 4)),
      });
      expect(fresh.isExpired, isFalse);
      final stale = TrafficEtaSnapshot.fromCallable({
        'reason': 'ok',
        'expiresAt': DateTime.now().subtract(const Duration(minutes: 1)),
      });
      expect(stale.isExpired, isTrue);
      expect(stale.isAvailable, isFalse);
    });
  });

  group('PlannedRoute google geometry', () {
    test('waypointsForTrip prefers google geometry', () {
      final encoded = encodeTestPolyline([
        [3.1, 101.7],
        [3.2, 101.8],
      ]);
      final route = PlannedRoute(
        id: 'r1',
        name: 'A',
        stops: [
          const RouteWaypoint(latitude: 3.1, longitude: 101.7),
          const RouteWaypoint(latitude: 3.2, longitude: 101.8),
        ],
        waypoints: const [RouteWaypoint(latitude: 3.0, longitude: 101.6)],
        createdAt: DateTime.utc(2026),
        googleGeometry: GoogleRouteGeometry(
          encodedPolyline: encoded,
          stopHash: 'h',
          generatedAt: DateTime.utc(2026),
          expiresAt: DateTime.utc(2027),
        ),
      );
      final trip = route.waypointsForTrip(TripDirection.toSchool);
      expect(trip.length, 2);
      expect(trip.first.latitude, closeTo(3.1, 1e-4));
      final reversed = route.waypointsForTrip(TripDirection.fromSchool);
      expect(reversed.first.latitude, closeTo(3.2, 1e-4));
    });
  });
}

/// Minimal encoder mirroring Google's polyline algorithm for test fixtures.
String encodeTestPolyline(List<List<double>> points) {
  String encodeValue(int value) {
    var number = value < 0 ? ~(value << 1) : value << 1;
    final buffer = StringBuffer();
    while (number >= 0x20) {
      buffer.writeCharCode((0x20 | (number & 0x1f)) + 63);
      number >>= 5;
    }
    buffer.writeCharCode(number + 63);
    return buffer.toString();
  }

  var prevLat = 0;
  var prevLng = 0;
  final buffer = StringBuffer();
  for (final point in points) {
    final lat5 = (point[0] * 1e5).round();
    final lng5 = (point[1] * 1e5).round();
    buffer.write(encodeValue(lat5 - prevLat));
    buffer.write(encodeValue(lng5 - prevLng));
    prevLat = lat5;
    prevLng = lng5;
  }
  return buffer.toString();
}
