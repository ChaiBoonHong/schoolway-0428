import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/map/map_markers.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/widgets/debug_bus_joystick.dart';

void main() {
  testWidgets('fleet bus marker centers a Font Awesome bus in a circle', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: buildFleetBusMarkerWidget(
              busId: 'bus-001',
              busLabel: 'BUS-001',
            ),
          ),
        ),
      ),
    );

    final circleFinder = find.byKey(
      const ValueKey('fleet-bus-marker-circle-bus-001'),
    );
    final iconFinder = find.byKey(
      const ValueKey('fleet-bus-marker-icon-bus-001'),
    );
    final circle = tester.widget<Container>(circleFinder);
    final decoration = circle.decoration! as BoxDecoration;
    final icon = tester.widget<FaIcon>(iconFinder);

    expect(decoration.shape, BoxShape.circle);
    expect(circle.alignment, Alignment.center);
    expect(icon.icon!.codePoint, FontAwesomeIcons.bus.codePoint);
    expect(icon.icon!.fontFamily, FontAwesomeIcons.bus.fontFamily);
    expect(tester.getCenter(iconFinder), tester.getCenter(circleFinder));
  });

  testWidgets('fleet bus marker draws a tail below the circle', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: buildFleetBusMarkerWidget(
              busId: 'bus-001',
              busLabel: 'BUS-001',
            ),
          ),
        ),
      ),
    );

    final painter = tester
        .widgetList<CustomPaint>(
          find.byWidgetPredicate(
            (w) =>
                w is CustomPaint &&
                w.painter.runtimeType.toString() == '_MarkerTailPainter',
          ),
        )
        .first;

    expect(painter.size, const Size(12, 5));
  });

  testWidgets('route planner pin uses brand primary, not danger red', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: buildRoutePlannerPinWidget(1))),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.location_on));
    expect(icon.color, SchoolWayTheme.primary);
    expect(icon.color, isNot(SchoolWayTheme.danger));
  });

  testWidgets('stop pin renders a custom badge label and the stop number', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: buildStopNumberWidget(number: 2, badgeLabel: '~4 min'),
          ),
        ),
      ),
    );

    expect(find.text('~4 min'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('student'), findsNothing);
  });

  testWidgets('stop pin keeps the student-count caption when no badge given', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: buildStopNumberWidget(number: 3, studentCount: 5),
          ),
        ),
      ),
    );

    expect(find.text('5 students'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('my location marker centres a halo dot on the position', (
    tester,
  ) async {
    const position = LatLng(3.14, 101.68);
    final marker = buildMyLocationMarker(id: 't', position: position);

    expect(marker.id, 't');
    expect(marker.latitude, position.latitude);
    expect(marker.longitude, position.longitude);
    expect(marker.width, 28);
    expect(marker.height, 28);
    expect(marker.alignment, Alignment.center);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(key: const ValueKey('host'), child: marker.child),
        ),
      ),
    );

    final containers = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byKey(const ValueKey('host')),
            matching: find.byType(Container),
          ),
        )
        .toList();

    expect(containers.length, 2);
    final halo = containers.first.decoration! as BoxDecoration;
    expect(halo.shape, BoxShape.circle);
    expect(halo.color, SchoolWayTheme.info.withValues(alpha: 0.25));
    final dot = containers.last.decoration! as BoxDecoration;
    expect(dot.shape, BoxShape.circle);
    expect(dot.color, SchoolWayTheme.info);
    expect((dot.border! as Border).top.color, SchoolWayTheme.surface);
  });

  testWidgets('debug joystick is labelled and supports arrow keys', (
    tester,
  ) async {
    var direction = const Offset(99, 99);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: DebugBusJoystick(
              semanticLabel: 'Move simulated bus',
              onDirectionChanged: (value) => direction = value,
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Move simulated bus'), findsOneWidget);

    await tester.tap(find.byType(DebugBusJoystick));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    expect(direction, const Offset(1, 0));

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(direction, Offset.zero);
  });

  for (final size in <Size>[
    const Size(390, 844),
    const Size(800, 1024),
    const Size(1280, 800),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'map controls fit ${size.width.toInt()}px in ${brightness.name} mode',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: Stack(
                  children: [
                    Positioned(
                      top: 72,
                      left: 16,
                      child: DebugBusJoystick(
                        size: 120,
                        semanticLabel: 'Move simulated bus',
                        onDirectionChanged: (_) {},
                      ),
                    ),
                    const Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: 90,
                        height: 72,
                        child: _BusMarkerPreview(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          expect(tester.takeException(), isNull);
          expect(find.byType(DebugBusJoystick), findsOneWidget);
          expect(
            find.byKey(const ValueKey('fleet-bus-marker-circle-bus-001')),
            findsOneWidget,
          );
        },
      );
    }
  }
}

class _BusMarkerPreview extends StatelessWidget {
  const _BusMarkerPreview();

  @override
  Widget build(BuildContext context) {
    return buildFleetBusMarkerWidget(busId: 'bus-001', busLabel: 'BUS-001');
  }
}
