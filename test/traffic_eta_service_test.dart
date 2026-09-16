import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/models/traffic_eta_snapshot.dart';
import 'package:schoolway/services/traffic_eta_service.dart';

void main() {
  TrafficEtaSnapshot snapshot({
    String reason = 'ok',
    bool cached = false,
    bool stale = false,
    DateTime? expiresAt,
  }) {
    return TrafficEtaSnapshot(
      sessionId: 's1',
      reason: reason == 'ok'
          ? TrafficEtaReason.ok
          : trafficEtaReasonFromString(reason),
      cached: cached,
      stale: stale,
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(minutes: 4)),
    );
  }

  test('refresh publishes available state for a live snapshot', () async {
    final service = TrafficEtaService(fetch: (_) async => snapshot());
    addTearDown(service.dispose);

    service.start('s1');
    await Future<void>.delayed(Duration.zero);
    expect(service.state.value.isAvailable, isTrue);
    expect(service.state.value.snapshot, isNotNull);
  });

  test('refresh publishes unavailable for a stale snapshot', () async {
    final service = TrafficEtaService(
      fetch: (_) async => snapshot(reason: 'stale-gps'),
    );
    addTearDown(service.dispose);

    service.start('s1');
    await Future<void>.delayed(Duration.zero);
    expect(service.state.value.status, TrafficEtaStatus.unavailable);
  });

  test('refresh publishes unavailable when expired', () async {
    final service = TrafficEtaService(
      fetch: (_) async => snapshot(
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );
    addTearDown(service.dispose);

    service.start('s1');
    await Future<void>.delayed(Duration.zero);
    expect(service.state.value.status, TrafficEtaStatus.unavailable);
  });

  test('refresh publishes unavailable on fetch error', () async {
    final service = TrafficEtaService(
      fetch: (_) async => throw Exception('boom'),
    );
    addTearDown(service.dispose);

    service.start('s1');
    await Future<void>.delayed(Duration.zero);
    expect(service.state.value.status, TrafficEtaStatus.unavailable);
    expect(service.state.value.error, isNotNull);
  });

  test(
    'refresh keeps the last valid ETA during a transient fetch error',
    () async {
      var calls = 0;
      final service = TrafficEtaService(
        fetch: (_) async {
          calls++;
          if (calls == 1) return snapshot();
          throw Exception('temporary network failure');
        },
      );
      addTearDown(service.dispose);

      service.start('s1');
      await Future<void>.delayed(Duration.zero);
      await service.refresh();

      expect(service.state.value.status, TrafficEtaStatus.available);
      expect(service.state.value.snapshot, isNotNull);
      expect(service.state.value.error, isNotNull);
    },
  );

  test('refresh keeps the existing ETA visible while a newer value loads', () async {
    final nextResponse = Completer<TrafficEtaSnapshot>();
    var calls = 0;
    final service = TrafficEtaService(
      fetch: (_) {
        calls++;
        return calls == 1 ? Future.value(snapshot()) : nextResponse.future;
      },
    );
    addTearDown(service.dispose);

    service.start('s1');
    await Future<void>.delayed(Duration.zero);
    final firstSnapshot = service.state.value.snapshot;

    final refresh = service.refresh();
    expect(service.state.value.status, TrafficEtaStatus.available);
    expect(service.state.value.snapshot, same(firstSnapshot));

    nextResponse.complete(snapshot());
    await refresh;
    expect(service.state.value.status, TrafficEtaStatus.available);
  });

  test('stop cancels generation so stale results are ignored', () async {
    var call = 0;
    final service = TrafficEtaService(
      fetch: (_) async {
        call++;
        if (call == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        return snapshot();
      },
    );
    addTearDown(service.dispose);

    service.start('s1');
    service.stop();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(service.state.value.status, TrafficEtaStatus.idle);
    expect(call, 1);
  });

  test('start on the same session is idempotent', () async {
    var call = 0;
    final service = TrafficEtaService(
      fetch: (_) async {
        call++;
        return snapshot();
      },
    );
    addTearDown(service.dispose);

    service.start('s1');
    await Future<void>.delayed(Duration.zero);
    final callsAfterFirst = call;
    service.start('s1');
    await Future<void>.delayed(Duration.zero);
    expect(call, callsAfterFirst);
  });

  test('state tracks elapsed local countdown time', () {
    final state = TrafficEtaState(
      countdownAnchor: DateTime.now().subtract(const Duration(seconds: 4)),
    );

    expect(state.elapsedCountdownSeconds, inInclusiveRange(4, 5));
  });
}
