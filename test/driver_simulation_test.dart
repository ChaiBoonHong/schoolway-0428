import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/widgets/debug_bus_joystick.dart';
import 'package:schoolway/l10n/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets(
    'DebugBusJoystick renders and operates with keyboard navigation',
    (tester) async {
      Offset? emitted;

      await tester.pumpWidget(
        _host(
          DebugBusJoystick(
            semanticLabel: 'Bus simulation joystick',
            onDirectionChanged: (dir) => emitted = dir,
          ),
        ),
      );

      expect(find.byType(DebugBusJoystick), findsOneWidget);
      expect(find.bySemanticsLabel('Bus simulation joystick'), findsOneWidget);

      // Tap to focus
      await tester.tap(find.byType(DebugBusJoystick));
      await tester.pump();

      // Test Arrow Up
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(emitted, const Offset(0, -1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(emitted, Offset.zero);

      // Test Arrow Down
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(emitted, const Offset(0, 1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(emitted, Offset.zero);

      // Test Arrow Left
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(emitted, const Offset(-1, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(emitted, Offset.zero);

      // Test Arrow Right
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(emitted, const Offset(1, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(emitted, Offset.zero);
    },
  );
}
