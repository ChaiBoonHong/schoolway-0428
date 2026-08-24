import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:latlong2/latlong.dart';
import 'package:schoolway/core/widgets/debug_bus_joystick.dart';
import 'package:schoolway/core/widgets/fleet_bus_marker.dart';

void main() {
  testWidgets('fleet bus marker centers a Font Awesome bus in a circle', (
    tester,
  ) async {
    final marker = buildFleetBusMarker(
      point: const LatLng(4.31591, 101.12330),
      busId: 'bus-001',
      busLabel: 'BUS-001',
    );

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: marker.child)));

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
                    Align(
                      alignment: Alignment.center,
                      child: buildFleetBusMarker(
                        point: const LatLng(4.31591, 101.12330),
                        busId: 'bus-001',
                        busLabel: 'BUS-001',
                      ).child,
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
