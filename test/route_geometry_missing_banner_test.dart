import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/widgets/route_geometry_missing_banner.dart';
import 'package:schoolway/l10n/app_localizations.dart';

Widget _host() => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: const Scaffold(body: Center(child: RouteGeometryMissingBanner())),
);

void main() {
  testWidgets('renders the localized geometry-missing notice', (tester) async {
    await tester.pumpWidget(_host());

    expect(find.byType(RouteGeometryMissingBanner), findsOneWidget);
    expect(find.textContaining('Route geometry unavailable'), findsOneWidget);
  });
}
