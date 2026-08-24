import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/preferences/app_preferences.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/features/shell/app_settings_screen.dart';
import 'package:schoolway/l10n/app_localizations.dart';

class _TestPreferencesNotifier extends AppPreferencesNotifier {
  @override
  AppPreferences build() => const AppPreferences.defaults();
}

void main() {
  testWidgets('diagnostics settings expose local user-controlled actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appPreferencesProvider.overrideWith(_TestPreferencesNotifier.new),
        ],
        child: MaterialApp(
          theme: SchoolWayTheme.light,
          darkTheme: SchoolWayTheme.dark,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AppSettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.scrollUntilVisible(find.text('Diagnostics'), 300);

    expect(find.text('Diagnostics'), findsOneWidget);
    expect(find.text('Share diagnostic log'), findsOneWidget);
    expect(find.text('Save diagnostic log'), findsOneWidget);
    expect(find.text('Copy latest incident reference'), findsOneWidget);
    expect(find.text('Clear diagnostic history'), findsOneWidget);
  });
}
