import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/features/admin/quick_setup_wizard.dart';
import 'package:schoolway/l10n/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

Future<void> _fillStudentFields(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'S001');
  await tester.enterText(fields.at(1), 'Aisyah');
  await tester.enterText(fields.at(2), 'Lim');
  await tester.enterText(fields.at(3), 'NFC-001');
  await tester.pump();
}

void main() {
  testWidgets('next stays disabled until student fields are filled', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const QuickSetupWizard()));
    await tester.pump();

    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );

    await _fillStudentFields(tester);

    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('student step exposes every required field', (tester) async {
    await tester.pumpWidget(_host(const QuickSetupWizard()));
    await tester.pump();

    expect(find.text('Student ID *'), findsOneWidget);
    expect(find.text('First Name *'), findsOneWidget);
    expect(find.text('Last Name *'), findsOneWidget);
    expect(find.text('K1'), findsOneWidget);
    expect(find.text('NFC Card ID *'), findsOneWidget);
  });
}
