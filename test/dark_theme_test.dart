import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/widgets/schoolway_components.dart';
import 'package:schoolway/core/widgets/traffic_eta_chip.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/traffic_eta_service.dart';

Widget _buildDarkTestApp({required Widget child}) {
  return MaterialApp(
    theme: SchoolWayTheme.light,
    darkTheme: SchoolWayTheme.dark,
    themeMode: ThemeMode.dark,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SchoolWayTheme.dark Specifications', () {
    test('provides complete M3 surface containers and accessible colors', () {
      final darkTheme = SchoolWayTheme.dark;
      final scheme = darkTheme.colorScheme;

      expect(scheme.brightness, Brightness.dark);
      expect(scheme.surface, SchoolWayTheme.darkSurface);
      expect(scheme.onSurface, SchoolWayTheme.darkText);
      expect(scheme.surfaceContainer, SchoolWayTheme.darkSurface);
      expect(scheme.surfaceContainerHigh, const Color(0xFF163246));
      expect(scheme.surfaceContainerHighest, const Color(0xFF1D3E56));
      expect(scheme.outline, SchoolWayTheme.darkBorder);
      expect(scheme.error, const Color(0xFFFFB4AB));

      expect(darkTheme.scaffoldBackgroundColor, SchoolWayTheme.darkBackground);
    });

    test(
      'configures AppBar, Chip, Dialog, Sheet, and Button themes in dark mode',
      () {
        final darkTheme = SchoolWayTheme.dark;

        // AppBar
        expect(
          darkTheme.appBarTheme.backgroundColor,
          SchoolWayTheme.darkBackground,
        );
        expect(darkTheme.appBarTheme.foregroundColor, SchoolWayTheme.darkText);
        expect(darkTheme.appBarTheme.elevation, 0);
        expect(
          darkTheme.appBarTheme.titleTextStyle?.color,
          SchoolWayTheme.darkText,
        );

        // Card
        expect(darkTheme.cardTheme.color, SchoolWayTheme.darkSurface);

        // Dialog & BottomSheet
        expect(
          darkTheme.dialogTheme.backgroundColor,
          SchoolWayTheme.darkSurface,
        );
        expect(
          darkTheme.bottomSheetTheme.backgroundColor,
          SchoolWayTheme.darkSurface,
        );

        // Chip
        expect(darkTheme.chipTheme.backgroundColor, SchoolWayTheme.darkSurface);

        // SnackBar
        expect(darkTheme.snackBarTheme.behavior, SnackBarBehavior.floating);

        // Elevated button
        expect(
          darkTheme.elevatedButtonTheme.style?.textStyle
              ?.resolve({})
              ?.fontFamily,
          'Lexend',
        );

        // TabBar
        expect(darkTheme.tabBarTheme.indicatorColor, const Color(0xFF48CAE4));
      },
    );

    test(
      'registers SchoolWayColors ThemeExtension on light and dark themes',
      () {
        final lightExt = SchoolWayTheme.light.extension<SchoolWayColors>();
        final darkExt = SchoolWayTheme.dark.extension<SchoolWayColors>();

        expect(lightExt, isNotNull);
        expect(darkExt, isNotNull);

        expect(lightExt!.brandNavy, SchoolWayTheme.navy);
        expect(lightExt.cardBackground, SchoolWayTheme.surface);

        expect(darkExt!.brandNavy, SchoolWayTheme.darkText);
        expect(darkExt.cardBackground, SchoolWayTheme.darkSurface);
        expect(darkExt.cardBorder, SchoolWayTheme.darkBorder);
        expect(darkExt.badgeSuccess, SchoolWayTheme.successBright);
        expect(darkExt.badgeWarning, const Color(0xFFFFB74D));
      },
    );
  });

  group('SchoolWayColors Extension Behavior', () {
    test('copyWith works correctly', () {
      final original = SchoolWayColors.dark;
      final copy = original.copyWith(brandNavy: Colors.amber);

      expect(copy.brandNavy, Colors.amber);
      expect(copy.cardBackground, original.cardBackground);
      expect(copy.cardBorder, original.cardBorder);
    });

    test('lerp works correctly', () {
      final light = SchoolWayColors.light;
      final dark = SchoolWayColors.dark;

      final mid = light.lerp(dark, 0.5);
      expect(mid.brandNavy, Color.lerp(light.brandNavy, dark.brandNavy, 0.5));
      expect(
        mid.cardBackground,
        Color.lerp(light.cardBackground, dark.cardBackground, 0.5),
      );
    });

    testWidgets(
      'resolves dark tokens in dark mode and light tokens in light mode',
      (tester) async {
        late SchoolWayColors resolvedDarkColors;
        late SchoolWayColors resolvedLightColors;

        await tester.pumpWidget(
          MaterialApp(
            theme: SchoolWayTheme.light,
            darkTheme: SchoolWayTheme.dark,
            themeMode: ThemeMode.dark,
            home: Builder(
              builder: (context) {
                resolvedDarkColors = context.schoolWayColors;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(resolvedDarkColors.brandNavy, SchoolWayTheme.darkText);
        expect(resolvedDarkColors.cardBackground, SchoolWayTheme.darkSurface);

        await tester.pumpWidget(
          MaterialApp(
            theme: SchoolWayTheme.light,
            darkTheme: SchoolWayTheme.dark,
            themeMode: ThemeMode.light,
            home: Builder(
              builder: (context) {
                resolvedLightColors = context.schoolWayColors;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(resolvedLightColors.brandNavy, SchoolWayTheme.navy);
        expect(resolvedLightColors.cardBackground, SchoolWayTheme.surface);
      },
    );
  });

  group('Dark Theme Component Rendering Tests', () {
    testWidgets('TrafficEtaChip renders theme colors in dark mode', (
      tester,
    ) async {
      final state = TrafficEtaState(
        status: TrafficEtaStatus.available,
        snapshot: TrafficEtaSnapshot(
          sessionId: 's1',
          reason: TrafficEtaReason.ok,
          generatedAt: DateTime.now().subtract(const Duration(minutes: 2)),
          expiresAt: DateTime.now().add(const Duration(minutes: 4)),
        ),
        lastUpdated: DateTime.now(),
      );

      await tester.pumpWidget(
        _buildDarkTestApp(child: TrafficEtaChip(state: state)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TrafficEtaChip), findsOneWidget);
    });

    testWidgets(
      'SchoolWayStatusBadge renders high-contrast badges in dark mode',
      (tester) async {
        await tester.pumpWidget(
          _buildDarkTestApp(
            child: Column(
              children: const [
                SchoolWayStatusBadge(
                  label: 'Active',
                  status: SchoolWayStatus.success,
                ),
                SchoolWayStatusBadge(
                  label: 'Pending',
                  status: SchoolWayStatus.warning,
                ),
                SchoolWayStatusBadge(
                  label: 'Alert',
                  status: SchoolWayStatus.danger,
                ),
                SchoolWayStatusBadge(
                  label: 'Info',
                  status: SchoolWayStatus.info,
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Active'), findsOneWidget);
        expect(find.text('Pending'), findsOneWidget);
        expect(find.text('Alert'), findsOneWidget);
        expect(find.text('Info'), findsOneWidget);
      },
    );
  });
}
