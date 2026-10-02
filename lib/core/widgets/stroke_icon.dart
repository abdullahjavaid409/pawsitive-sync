import 'package:flutter/material.dart';

enum StrokeIconKind {
  paw,
  check,
  calendar,
  people,
  file,
  plus,
  close,
  chevronLeft,
  refresh,
  bell,
  phone,
  camera,
}

class StrokeIcon extends StatelessWidget {
  const StrokeIcon(
    this.kind, {
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = 1.75,
  });

  final StrokeIconKind kind;
  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final paintColor =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    return CustomPaint(
      size: Size.square(size),
      painter: _StrokePainter(kind, paintColor, strokeWidth),
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.kind, this.color, this.strokeWidth);

  final StrokeIconKind kind;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (kind) {
      case StrokeIconKind.paw:
        canvas.drawCircle(const Offset(5.5, 10), 2, paint);
        canvas.drawCircle(const Offset(9.5, 5.5), 2, paint);
        canvas.drawCircle(const Offset(14.5, 5.5), 2, paint);
        canvas.drawCircle(const Offset(18.5, 10), 2, paint);
        canvas.drawPath(
          Path()
            ..moveTo(12, 12)
            ..cubicTo(9, 12, 6, 16, 6, 18.5)
            ..cubicTo(6, 20, 7.2, 21, 8.7, 20.7)
            ..cubicTo(9.9, 20.4, 10.8, 20, 12, 20)
            ..cubicTo(13.2, 20, 14.1, 20.4, 15.3, 20.7)
            ..cubicTo(16.8, 21, 18, 20, 18, 18.5)
            ..cubicTo(18, 16, 15, 12, 12, 12)
            ..close(),
          paint,
        );
      case StrokeIconKind.check:
        canvas.drawPath(
          Path()
            ..moveTo(5, 12.5)
            ..lineTo(9.5, 17)
            ..lineTo(19, 7.5),
          paint..strokeWidth = strokeWidth + 0.6,
        );
      case StrokeIconKind.calendar:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 4.5, 18, 16.5),
            const Radius.circular(2.5),
          ),
          paint,
        );
        canvas.drawLine(const Offset(3, 9.5), const Offset(21, 9.5), paint);
        canvas.drawLine(const Offset(8, 2.5), const Offset(8, 6.5), paint);
        canvas.drawLine(const Offset(16, 2.5), const Offset(16, 6.5), paint);
      case StrokeIconKind.people:
        canvas.drawCircle(const Offset(9, 8), 3.5, paint);
        canvas.drawPath(
          Path()
            ..moveTo(2.5, 20)
            ..cubicTo(2.5, 16.4, 5.4, 14, 9, 14)
            ..cubicTo(12.6, 14, 15.5, 16.4, 15.5, 20),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(16, 4.6)
            ..cubicTo(18.2, 5.2, 19.6, 7.2, 19.6, 9.4)
            ..cubicTo(19.6, 11.6, 18.2, 13.6, 16, 14.2),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(18.5, 14.3)
            ..cubicTo(20.4, 15.1, 21.5, 17.2, 21.5, 20),
          paint,
        );
      case StrokeIconKind.file:
        canvas.drawPath(
          Path()
            ..moveTo(14, 3)
            ..lineTo(7, 3)
            ..cubicTo(5.9, 3, 5, 3.9, 5, 5)
            ..lineTo(5, 19)
            ..cubicTo(5, 20.1, 5.9, 21, 7, 21)
            ..lineTo(17, 21)
            ..cubicTo(18.1, 21, 19, 20.1, 19, 19)
            ..lineTo(19, 8)
            ..close(),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(14, 3)
            ..lineTo(14, 8)
            ..lineTo(19, 8),
          paint,
        );
        canvas.drawLine(const Offset(9, 13), const Offset(15, 13), paint);
        canvas.drawLine(const Offset(9, 17), const Offset(15, 17), paint);
      case StrokeIconKind.plus:
        canvas.drawLine(const Offset(12, 5), const Offset(12, 19), paint);
        canvas.drawLine(const Offset(5, 12), const Offset(19, 12), paint);
      case StrokeIconKind.close:
        canvas.drawLine(const Offset(6, 6), const Offset(18, 18), paint);
        canvas.drawLine(const Offset(18, 6), const Offset(6, 18), paint);
      case StrokeIconKind.chevronLeft:
        canvas.drawPath(
          Path()
            ..moveTo(15, 6)
            ..lineTo(9, 12)
            ..lineTo(15, 18),
          paint,
        );
      case StrokeIconKind.refresh:
        canvas.drawPath(
          Path()
            ..moveTo(20, 5)
            ..lineTo(17, 2)
            ..lineTo(17, 8),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(4, 11)
            ..cubicTo(4, 7, 8, 4, 12, 4)
            ..lineTo(17, 4),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(4, 19)
            ..lineTo(7, 22)
            ..lineTo(7, 16),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(20, 13)
            ..cubicTo(20, 17, 16, 20, 12, 20)
            ..lineTo(7, 20),
          paint,
        );
      case StrokeIconKind.bell:
        canvas.drawPath(
          Path()
            ..moveTo(6, 8)
            ..cubicTo(6, 4.7, 8.7, 2, 12, 2)
            ..cubicTo(15.3, 2, 18, 4.7, 18, 8)
            ..cubicTo(18, 15, 21, 17, 21, 17)
            ..lineTo(3, 17)
            ..cubicTo(3, 17, 6, 15, 6, 8),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(10, 20)
            ..cubicTo(10.4, 21.2, 11.1, 22, 12, 22)
            ..cubicTo(12.9, 22, 13.6, 21.2, 14, 20),
          paint,
        );
      case StrokeIconKind.phone:
        canvas.drawPath(
          Path()
            ..moveTo(7, 3)
            ..lineTo(10, 3)
            ..lineTo(11.2, 7.2)
            ..lineTo(9.2, 8.6)
            ..cubicTo(10.4, 11, 13, 13.6, 15.4, 14.8)
            ..lineTo(16.8, 12.8)
            ..lineTo(21, 14)
            ..lineTo(21, 17)
            ..cubicTo(21, 18.7, 19.6, 20.2, 17.8, 19.8)
            ..cubicTo(11.2, 18.4, 5.6, 12.8, 4.2, 6.2)
            ..cubicTo(3.8, 4.4, 5.3, 3, 7, 3),
          paint,
        );
      case StrokeIconKind.camera:
        canvas.drawPath(
          Path()
            ..moveTo(4, 8)
            ..lineTo(7, 8)
            ..lineTo(9, 5)
            ..lineTo(15, 5)
            ..lineTo(17, 8)
            ..lineTo(20, 8)
            ..cubicTo(20.6, 8, 21, 8.4, 21, 9)
            ..lineTo(21, 19)
            ..cubicTo(21, 19.6, 20.6, 20, 20, 20)
            ..lineTo(4, 20)
            ..cubicTo(3.4, 20, 3, 19.6, 3, 19)
            ..lineTo(3, 9)
            ..cubicTo(3, 8.4, 3.4, 8, 4, 8),
          paint,
        );
        canvas.drawCircle(const Offset(12, 13.5), 3.5, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter oldDelegate) {
    return oldDelegate.kind != kind ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
