import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Virtual joystick for driver-controlled GPS simulation.
/// [onDirectionChanged] is called with a normalised vector in [-1, 1] for each
/// axis; magnitude is capped at 1. Emits [Offset.zero] on release.
class DebugBusJoystick extends StatefulWidget {
  const DebugBusJoystick({
    super.key,
    required this.onDirectionChanged,
    required this.semanticLabel,
    this.size = 140,
  });

  final ValueChanged<Offset> onDirectionChanged;
  final String semanticLabel;
  final double size;

  @override
  State<DebugBusJoystick> createState() => _DebugBusJoystickState();
}

class _DebugBusJoystickState extends State<DebugBusJoystick> {
  Offset _knob = Offset.zero;
  final FocusNode _focusNode = FocusNode(debugLabel: 'Bus simulation joystick');

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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isArrow =
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    if (!isArrow) return KeyEventResult.ignored;

    if (event is KeyUpEvent) {
      _release();
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final direction = switch (key) {
      LogicalKeyboardKey.arrowUp => const Offset(0, -1),
      LogicalKeyboardKey.arrowDown => const Offset(0, 1),
      LogicalKeyboardKey.arrowLeft => const Offset(-1, 0),
      _ => const Offset(1, 0),
    };
    setState(() => _knob = direction * _maxR);
    widget.onDirectionChanged(direction);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: widget.semanticLabel,
      focusable: true,
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: SizedBox(
          width: s,
          height: s,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _focusNode.requestFocus,
            onPanDown: (d) {
              _focusNode.requestFocus();
              _update(d.localPosition);
            },
            onPanUpdate: (d) => _update(d.localPosition),
            onPanEnd: (_) => _release(),
            onPanCancel: _release,
            child: CustomPaint(
              painter: _JoystickPainter(
                knob: _knob,
                outerR: _outerR,
                maxR: _maxR,
                knobR: _knobR,
                surfaceColor: colors.surface,
                primaryColor: colors.primary,
                guideColor: colors.onSurface,
              ),
              size: Size(s, s),
            ),
          ),
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
    required this.surfaceColor,
    required this.primaryColor,
    required this.guideColor,
  });

  final Offset knob;
  final double outerR;
  final double maxR;
  final double knobR;
  final Color surfaceColor;
  final Color primaryColor;
  final Color guideColor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);

    // Outer ring fill.
    canvas.drawCircle(
      c,
      outerR,
      Paint()..color = surfaceColor.withValues(alpha: 0.88),
    );

    // Outer ring border.
    canvas.drawCircle(
      c,
      outerR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = primaryColor.withValues(alpha: 0.55),
    );

    // Inner guide ring (shows travel boundary of the knob centre).
    canvas.drawCircle(
      c,
      maxR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = primaryColor.withValues(alpha: 0.20),
    );

    // Direction tick marks — drawn near the ring edge, not from the centre.
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = guideColor.withValues(alpha: 0.28);
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
    canvas.drawCircle(kc, knobR, Paint()..color = primaryColor);

    // Gloss highlight on knob.
    canvas.drawCircle(
      kc + const Offset(-4, -5),
      knobR * 0.28,
      Paint()..color = surfaceColor.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter old) =>
      old.knob != knob ||
      old.outerR != outerR ||
      old.maxR != maxR ||
      old.knobR != knobR ||
      old.surfaceColor != surfaceColor ||
      old.primaryColor != primaryColor ||
      old.guideColor != guideColor;
}
