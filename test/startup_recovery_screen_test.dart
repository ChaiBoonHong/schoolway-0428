import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/features/shell/startup_recovery_screen.dart';
import 'package:schoolway/l10n/app_localizations.dart';

void main() {
  testWidgets('startup recovery is accessible at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: SchoolWayTheme.light,
        darkTheme: SchoolWayTheme.dark,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: StartupRecoveryScreen(
          incidentId: 'SW-A31F92',
          onRetry: () async {},
        ),
      ),
    );

    expect(find.text('SchoolWay could not finish starting.'), findsOneWidget);
    expect(find.textContaining('SW-A31F92'), findsOneWidget);
    expect(find.bySemanticsLabel('Try again'), findsOneWidget);
    expect(find.bySemanticsLabel('Open diagnostics'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
