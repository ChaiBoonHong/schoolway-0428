import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/widgets/nfc_scan_feedback.dart';

void main() {
  testWidgets('new NFC feedback immediately replaces the previous student', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (builderContext) {
              context = builderContext;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    NfcScanFeedback.show(
      context,
      message: 'Saved: Alice Tan',
      backgroundColor: SchoolWayTheme.success,
    );
    await tester.pump();
    expect(find.text('Saved: Alice Tan'), findsOneWidget);

    NfcScanFeedback.show(
      context,
      message: 'Saved: Ben Lee',
      backgroundColor: SchoolWayTheme.success,
    );
    await tester.pump();

    expect(find.text('Saved: Alice Tan'), findsNothing);
    expect(find.text('Saved: Ben Lee'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(NfcScanFeedback.duration);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Saved: Ben Lee'), findsNothing);
  });
}
