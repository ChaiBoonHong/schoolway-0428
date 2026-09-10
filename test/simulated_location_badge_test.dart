import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/widgets/simulated_location_badge.dart';
import 'package:schoolway/l10n/app_localizations.dart';

void main() {
  for (final size in <Size>[
    const Size(390, 844),
    const Size(800, 1024),
    const Size(1280, 800),
  ]) {
    for (final themeMode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'simulation badge fits ${size.width.toInt()}px in ${themeMode.name}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              theme: SchoolWayTheme.light,
              darkTheme: SchoolWayTheme.dark,
              themeMode: themeMode,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 220,
                      child: SimulatedLocationBadge(),
                    ),
                  ),
                ),
              ),
            ),
          );

          expect(find.text('Simulation active'), findsOneWidget);
          expect(find.byIcon(Icons.science_outlined), findsOneWidget);
          expect(find.bySemanticsLabel('Simulation active'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
