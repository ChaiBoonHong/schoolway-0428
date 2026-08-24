import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/features/admin/widgets/csv_preview_summary.dart';
import 'package:schoolway/l10n/app_localizations.dart';

void main() {
  Widget buildSummary({
    required ThemeMode themeMode,
    required double textScale,
  }) {
    return MaterialApp(
      theme: SchoolWayTheme.light,
      darkTheme: SchoolWayTheme.dark,
      themeMode: themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const Padding(
            padding: EdgeInsets.all(SchoolWayTheme.spacing16),
            child: CsvPreviewSummary(
              totalRows: 20,
              validRows: 20,
              invalidRows: 0,
              duplicateRows: 0,
              existingRows: 1,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('reflows without clipping at supported widths and themes', (
    tester,
  ) async {
    final view = tester.view;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
    view.devicePixelRatio = 1;

    for (final width in <double>[320, 834, 1440]) {
      for (final themeMode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
        view.physicalSize = Size(width, 1000);
        await tester.pumpWidget(
          buildSummary(themeMode: themeMode, textScale: 2),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('20 records total'), findsOneWidget);
        expect(find.text('Valid'), findsOneWidget);
        expect(find.text('Invalid'), findsOneWidget);
        expect(find.text('Duplicates'), findsOneWidget);
        expect(find.text('Existing in DB'), findsOneWidget);
      }
    }
  });

  testWidgets('exposes each status and total to assistive technology', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        buildSummary(themeMode: ThemeMode.light, textScale: 1),
      );
      await tester.pumpAndSettle();

      expect(find.text('20 records total'), findsOneWidget);
      expect(find.bySemanticsLabel('Valid: 20'), findsOneWidget);
      expect(find.bySemanticsLabel('Invalid: 0'), findsOneWidget);
      expect(find.bySemanticsLabel('Duplicates: 0'), findsOneWidget);
      expect(find.bySemanticsLabel('Existing in DB: 1'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
