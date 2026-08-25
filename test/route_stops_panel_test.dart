import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/features/admin/widgets/route_stops_panel.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/models/models.dart';

RouteWaypoint _stop(double lat) =>
    RouteWaypoint(latitude: lat, longitude: 101.13);

Widget _host(RouteStopsPanel panel) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: panel),
);

void main() {
  testWidgets('shows the stop counter and fires remove callback', (
    tester,
  ) async {
    var removedAt = -1;
    await tester.pumpWidget(
      _host(
        RouteStopsPanel(
          stops: [_stop(4.31), _stop(4.32), _stop(4.33)],
          onReorder: (_, _) {},
          onRemove: (index) => removedAt = index,
          onSelect: (_) {},
          onClose: () {},
        ),
      ),
    );

    expect(find.text('3 / 26 stops'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

    await tester.tap(find.byTooltip('Remove stop').at(1));
    await tester.pumpAndSettle();
    expect(removedAt, 1);
  });

  testWidgets('flags plans above the Google stop limit', (tester) async {
    await tester.pumpWidget(
      _host(
        RouteStopsPanel(
          stops: List.generate(27, (i) => _stop(4.30 + i * 0.001)),
          maxStops: 26,
          onReorder: (_, _) {},
          onRemove: (_) {},
          onSelect: (_) {},
          onClose: () {},
        ),
      ),
    );

    expect(find.text('27 / 26 stops'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.textContaining('Google supports at most 26'), findsOneWidget);
  });

  testWidgets('notifies when a stop row is selected', (tester) async {
    var selectedAt = -1;
    await tester.pumpWidget(
      _host(
        RouteStopsPanel(
          stops: [_stop(4.31), _stop(4.32)],
          onReorder: (_, _) {},
          onRemove: (_) {},
          onSelect: (index) => selectedAt = index,
          onClose: () {},
        ),
      ),
    );

    await tester.tap(find.text('Stop 2'));
    await tester.pumpAndSettle();
    expect(selectedAt, 1);
  });
}
