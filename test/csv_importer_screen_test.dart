import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/features/admin/csv_importer_screen.dart';
import 'package:schoolway/l10n/app_localizations.dart';

void main() {
  testWidgets('CSV Management omits route maintenance', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: SchoolWayTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CsvImporterScreen(),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Export'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Import Wizard'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Route Maintenance'), findsNothing);
    expect(find.text('Rebuild Route Geometry (Google Maps)'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
