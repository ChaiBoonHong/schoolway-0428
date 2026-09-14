import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/features/admin/admin_home.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in <double>[360, 800, 1200]) {
    for (final themeMode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'overview cards have matching heights at ${width.toInt()}px in ${themeMode.name} mode',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: SchoolWayTheme.light,
              darkTheme: SchoolWayTheme.dark,
              themeMode: themeMode,
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: AdminOverviewMetrics(
                        activeBusesCount: 2,
                        studentsOnBoardCount: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          final activeBuses = tester.getRect(
            find.byKey(const ValueKey('active-buses-metric-card')),
          );
          final studentsOnBoard = tester.getRect(
            find.byKey(const ValueKey('students-on-board-metric-card')),
          );

          expect(activeBuses.height, studentsOnBoard.height);
        },
      );
    }
  }

  testWidgets('overview cards stay aligned at 200% text scaling', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SchoolWayTheme.light,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: AdminOverviewMetrics(
                activeBusesCount: 2,
                studentsOnBoardCount: 14,
              ),
            ),
          ),
        ),
      ),
    );

    final activeBuses = tester.getRect(
      find.byKey(const ValueKey('active-buses-metric-card')),
    );
    final studentsOnBoard = tester.getRect(
      find.byKey(const ValueKey('students-on-board-metric-card')),
    );

    expect(activeBuses.height, studentsOnBoard.height);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overview labels use light text in dark mode', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SchoolWayTheme.light,
        darkTheme: SchoolWayTheme.dark,
        themeMode: ThemeMode.dark,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: AdminOverviewMetrics(
              activeBusesCount: 2,
              studentsOnBoardCount: 14,
            ),
          ),
        ),
      ),
    );

    final activeBuses = tester.widget<Text>(find.text('Active Buses'));
    final studentsOnBoard = tester.widget<Text>(
      find.text('Students On Board'),
    );

    expect(activeBuses.style?.color, SchoolWayColors.dark.headerText);
    expect(studentsOnBoard.style?.color, SchoolWayColors.dark.headerText);
  });
}
