import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/features/admin/admin_home.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required double textScale,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: SchoolWayTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 800),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Center(
            child: SizedBox(
              width: 158,
              height: 288 * textScale,
              child: AdminReportCard(
                title: 'Daily Attendance Report',
                description:
                    'Class rosters with board, drop off, or absent; tap for scan times',
                icon: Icons.today,
                color: SchoolWayTheme.primary,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('fits a narrow phone card without overflow', (tester) async {
    await pumpCard(tester, textScale: 1);

    expect(find.text('Daily Attendance Report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits at 200 percent text scale', (tester) async {
    await pumpCard(tester, textScale: 2);

    expect(find.text('Daily Attendance Report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
