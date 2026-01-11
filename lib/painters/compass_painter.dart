import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Custom painter for compass direction indicator
/// Extracted from SignalLocatorPage for modularity
class CompassPainter extends CustomPainter {
  final double heading;
  final int? bestHeading;
  final bool isCalibrating;

  CompassPainter({
    required this.heading,
    this.bestHeading,
    this.isCalibrating = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Draw tick marks
    final tickPaint = Paint()
      ..color = Colors.grey[400]!
      ..strokeWidth = 1;

    for (int i = 0; i < 36; i++) {
      final angle = (i * 10 - 90) * math.pi / 180;
      final tickLength = i % 9 == 0 ? 15.0 : 8.0;
      final start = Offset(
        center.dx + (radius - tickLength) * math.cos(angle),
        center.dy + (radius - tickLength) * math.sin(angle),
      );
      final end = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(start, end, tickPaint);
    }

    // Draw best heading indicator
    if (bestHeading != null) {
      final bestAngle = (bestHeading! - 90) * math.pi / 180;
      final arrowPaint = Paint()
        ..color = Colors.green
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke;

      final arrowStart = Offset(
        center.dx + 30 * math.cos(bestAngle),
        center.dy + 30 * math.sin(bestAngle),
      );
      final arrowEnd = Offset(
        center.dx + (radius - 5) * math.cos(bestAngle),
        center.dy + (radius - 5) * math.sin(bestAngle),
      );
      canvas.drawLine(arrowStart, arrowEnd, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
