import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/widgets/slide_to_confirm.dart';

void main() {
  testWidgets('thumb is centered inside the initial circular track cap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('slide-to-confirm-capture'),
              child: SizedBox(
                width: 320,
                child: SlideToConfirm(
                  text: 'Slide to Start Trip',
                  baseColor: SchoolWayTheme.primary,
                  activeColor: SchoolWayTheme.accent,
                  onConfirm: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final fillCenter = tester.getCenter(
      find.byKey(const ValueKey('slide-to-confirm-fill')),
    );
    final thumbCenter = tester.getCenter(
      find.byKey(const ValueKey('slide-to-confirm-thumb')),
    );

    expect(thumbCenter.dx, closeTo(fillCenter.dx, 0.01));
    expect(thumbCenter.dy, closeTo(fillCenter.dy, 0.01));

    final capturePath = Platform.environment['SCHOOLWAY_SLIDER_CAPTURE'];
    if (capturePath != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('slide-to-confirm-capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(capturePath).writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
  });
}
