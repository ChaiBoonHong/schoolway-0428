import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Virtual joystick for debug GPS simulation.
/// [onDirectionChanged] is called with a normalised vector in [-1, 1] for each
/// axis; magnitude is capped at 1. Emits [Offset.zero] on release.
class DebugBusJoystick extends StatefulWidget {
  const DebugBusJoystick({
    super.key,
    required this.onDirectionChanged,
    this.size = 140,
  });

  final ValueChanged<Offset> onDirectionChanged;
  final double size;

  @override
  State<DebugBusJoystick> createState() => _DebugBusJoystickState();
}

class _DebugBusJoystickState extends State<DebugBusJoystick> {
  Offset _knob = Offset.zero;

  static const double _knobR = 22;

  /// Outer ring radius — leaves a 4 px visual border inside the widget box.
  double get _outerR => widget.size / 2 - 4;

  /// Maximum displacement of the knob centre — keeps the knob visually inside
  /// the ring at all times (ring edge − knob radius − 2 px gap).
  double get _maxR => _outerR - _knobR - 2;

  void _update(Offset localPos) {
    final center = Offset(widget.size / 2, widget.size / 2);
    var delta = localPos - center;
    final len = delta.distance;
    if (len > _maxR && len > 0) delta = delta * (_maxR / len);

    setState(() => _knob = delta);

    final nx = (delta.dx / _maxR).clamp(-1.0, 1.0);
    final ny = (delta.dy / _maxR).clamp(-1.0, 1.0);
    widget.onDirectionChanged(Offset(nx, ny));
  }

  void _release() {
    setState(() => _knob = Offset.zero);
    widget.onDirectionChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: GestureDetector(
        // opaque so drags don't fall through to the map beneath the panel.
        behavior: HitTestBehavior.opaque,
        onPanDown: (d) => _update(d.localPosition),
        onPanUpdate: (d) => _update(d.localPosition),
        onPanEnd: (_) => _release(),
        onPanCancel: _release,
        child: CustomPaint(
          painter: _JoystickPainter(
            knob: _knob,
            outerR: _outerR,
            maxR: _maxR,
            knobR: _knobR,
          ),
          size: Size(s, s),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter({
    required this.knob,
    required this.outerR,
    required this.maxR,
    required this.knobR,
  });

  final Offset knob;
  final double outerR;
  final double maxR;
  final double knobR;

  static const _blue = SchoolWayTheme.primary;
  static const _darkBlue = SchoolWayTheme.navy;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);

    // Outer ring fill.
    canvas.drawCircle(
      c,
      outerR,
      Paint()..color = SchoolWayTheme.surface.withValues(alpha: 0.95),
    );

    // Outer ring border.
    canvas.drawCircle(
      c,
      outerR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _blue.withValues(alpha: 0.40),
    );

    // Inner guide ring (shows travel boundary of the knob centre).
    canvas.drawCircle(
      c,
      maxR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _blue.withValues(alpha: 0.15),
    );

    // Direction tick marks — drawn near the ring edge, not from the centre.
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = _darkBlue.withValues(alpha: 0.22);
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        c + dir * (outerR * 0.62),
        c + dir * (outerR * 0.88),
        tickPaint,
      );
    }

    // Knob.
    final kc = c + knob;
    canvas.drawCircle(kc, knobR, Paint()..color = _blue);

    // Gloss highlight on knob.
    canvas.drawCircle(
      kc + const Offset(-4, -5),
      knobR * 0.28,
      Paint()..color = SchoolWayTheme.surface.withValues(alpha: 0.30),
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter old) =>
      old.knob != knob ||
      old.outerR != outerR ||
      old.maxR != maxR ||
      old.knobR != knobR;
}
