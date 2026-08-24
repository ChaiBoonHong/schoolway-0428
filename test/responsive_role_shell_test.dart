import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/widgets/responsive_role_shell.dart';

void main() {
  const destinations = [
    RoleDestination(
      label: 'Map',
      icon: Icons.map_outlined,
      selectedIcon: Icons.map,
    ),
    RoleDestination(
      label: 'Trips',
      icon: Icons.route_outlined,
      selectedIcon: Icons.route,
    ),
    RoleDestination(
      label: 'People',
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
    ),
  ];

  Future<void> pumpShell(
    WidgetTester tester, {
    required Size size,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: SchoolWayTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: ResponsiveRoleShell(
            title: 'Workspace',
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            destinations: destinations,
            children: const [
              Center(child: Text('Map content')),
              Center(child: Text('Trips content')),
              Center(child: Text('People content')),
              Center(child: Text('Profile content')),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('phone uses three-item bottom navigation and app-bar profile', (
    tester,
  ) async {
    await pumpShell(tester, size: const Size(390, 844), textScale: 2);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byTooltip('Profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet and desktop use a navigation rail', (tester) async {
    await pumpShell(tester, size: const Size(800, 900));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await pumpShell(tester, size: const Size(1280, 900));
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
    expect(tester.takeException(), isNull);
  });
}
