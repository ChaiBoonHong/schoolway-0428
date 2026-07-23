import 'package:flutter/material.dart';

class SlideToConfirm extends StatefulWidget {
  final VoidCallback onConfirm;
  final String text;
  final Color baseColor;
  final Color activeColor;

  const SlideToConfirm({
    super.key,
    required this.onConfirm,
    required this.text,
    required this.baseColor,
    required this.activeColor,
  });

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm>
    with SingleTickerProviderStateMixin {
  double _dragPosition = 0.0;
  bool _confirmed = false;
  late AnimationController _animController;
  double _currentMaxWidth = 0.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animController.addListener(() {
      if (mounted) {
        setState(() {
          _dragPosition = _animController.value * (_currentMaxWidth - 60);
        });
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double maxWidth) {
    if (_confirmed) return;
    _currentMaxWidth = maxWidth;
    _animController.stop();
    setState(() {
      _dragPosition += details.delta.dx;
      if (_dragPosition < 0) _dragPosition = 0;
      if (_dragPosition > maxWidth - 60) {
        _dragPosition = maxWidth - 60;
        _confirmed = true;
        widget.onConfirm();
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details, double maxWidth) {
    if (_confirmed) return;
    _currentMaxWidth = maxWidth;
    _animController.value = _dragPosition / (maxWidth - 60);
    _animController.reverse(from: _animController.value);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth;
      return Container(
        height: 60,
        decoration: BoxDecoration(
          color: widget.baseColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                widget.text,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  color: widget.baseColor.withValues(alpha: 0.8),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: _dragPosition + 60,
                decoration: BoxDecoration(
                  color: widget.activeColor,
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
            Positioned(
              left: _dragPosition,
              top: 4,
              bottom: 4,
              child: GestureDetector(
                onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d, maxWidth),
                onHorizontalDragEnd: (d) => _onHorizontalDragEnd(d, maxWidth),
                child: Container(
                  width: 52,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      )
                    ],
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: widget.baseColor,
                    size: 32,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
