import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/widgets/traffic_eta_chip.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/traffic_eta_service.dart';

Widget _wrap(
  TrafficEtaState state, {
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: Center(child: TrafficEtaChip(state: state)),
    ),
  );
}

TrafficEtaState _available({DateTime? expiresAt}) {
  return TrafficEtaState(
    status: TrafficEtaStatus.available,
    snapshot: TrafficEtaSnapshot(
      sessionId: 's1',
      reason: TrafficEtaReason.ok,
      generatedAt: DateTime.now().subtract(const Duration(minutes: 2)),
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(minutes: 4)),
    ),
    lastUpdated: DateTime.now(),
  );
}

void main() {
  for (final size in <Size>[
    const Size(390, 844),
    const Size(800, 1024),
    const Size(1280, 800),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'Traffic ETA chip fits ${size.width.toInt()}px in ${brightness.name}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(_wrap(_available(), brightness: brightness));
          expect(tester.takeException(), isNull);
          expect(find.byType(TrafficEtaChip), findsOneWidget);
          expect(find.textContaining('Traffic ETA updated'), findsOneWidget);
        },
      );
    }
  }

  testWidgets('chip shows unavailable when expired', (tester) async {
    await tester.pumpWidget(
      _wrap(
        _available(
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ),
    );
    expect(find.text('Traffic ETA unavailable'), findsOneWidget);
  });

  testWidgets('chip shows unavailable state for stale-gps reason', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const TrafficEtaState(
          status: TrafficEtaStatus.unavailable,
          snapshot: TrafficEtaSnapshot(
            sessionId: 's1',
            reason: TrafficEtaReason.staleGps,
          ),
        ),
      ),
    );
    expect(find.text('Traffic ETA unavailable'), findsOneWidget);
  });

  testWidgets('chip shows refreshing label while loading', (tester) async {
    await tester.pumpWidget(
      _wrap(const TrafficEtaState(status: TrafficEtaStatus.loading)),
    );
    expect(find.text('Refreshing traffic ETA…'), findsOneWidget);
  });
}
