import 'dart:math';
import 'package:flutter/material.dart';

/// Mesh Network Background Painter
///
/// Draws an animated node-and-edge network pattern that implies
/// connectivity without being distracting. Optimized for performance.
class MeshBackgroundPainter extends CustomPainter {
  final Color nodeColor;
  final Color lineColor;
  final Color glowColor;
  final double animationValue; // 0.0 to 1.0, loops
  final int nodeCount;

  // Cached values for performance
  late final List<_MeshNode> _nodes;
  late final Paint _nodePaint;
  late final Paint _linePaint;
  late final Paint _glowPaint;

  MeshBackgroundPainter({
    required this.nodeColor,
    required this.lineColor,
    required this.glowColor,
    this.animationValue = 0.0,
    this.nodeCount = 35,
  }) {
    _initPaints();
    _nodes = _generateNodes();
  }

  void _initPaints() {
    _nodePaint = Paint()
      ..color = nodeColor
      ..style = PaintingStyle.fill;

    _linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    _glowPaint = Paint()
      ..color = glowColor
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
  }

  List<_MeshNode> _generateNodes() {
    final random = Random(42); // Fixed seed for consistency
    return List.generate(nodeCount, (i) {
      return _MeshNode(
        baseX: random.nextDouble(),
        baseY: random.nextDouble(),
        radius: 2.0 + random.nextDouble() * 3.0,
        phase: random.nextDouble() * pi * 2,
        amplitude: 0.01 + random.nextDouble() * 0.02,
        speed: 0.5 + random.nextDouble() * 0.5,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Calculate animated positions
    final positions = <Offset>[];
    for (final node in _nodes) {
      final offsetX =
          sin(animationValue * pi * 2 * node.speed + node.phase) *
          node.amplitude;
      final offsetY =
          cos(animationValue * pi * 2 * node.speed + node.phase * 1.5) *
          node.amplitude;
      positions.add(
        Offset(
          (node.baseX + offsetX) * size.width,
          (node.baseY + offsetY) * size.height,
        ),
      );
    }

    // Draw connections (only nearby nodes)
    final maxDistance = size.width * 0.15;
    for (int i = 0; i < positions.length; i++) {
      for (int j = i + 1; j < positions.length; j++) {
        final distance = (positions[i] - positions[j]).distance;
        if (distance < maxDistance) {
          final opacity = 1.0 - (distance / maxDistance);
          _linePaint.color = lineColor.withAlpha((opacity * 0.6 * 255).round());
          canvas.drawLine(positions[i], positions[j], _linePaint);
        }
      }
    }

    // Draw nodes with glow
    for (int i = 0; i < positions.length; i++) {
      final pos = positions[i];
      final node = _nodes[i];

      // Subtle glow on some nodes
      if (i % 4 == 0) {
        canvas.drawCircle(pos, node.radius * 3, _glowPaint);
      }

      // Node
      canvas.drawCircle(pos, node.radius, _nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant MeshBackgroundPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.nodeColor != nodeColor ||
        oldDelegate.lineColor != lineColor;
  }
}

class _MeshNode {
  final double baseX;
  final double baseY;
  final double radius;
  final double phase;
  final double amplitude;
  final double speed;

  const _MeshNode({
    required this.baseX,
    required this.baseY,
    required this.radius,
    required this.phase,
    required this.amplitude,
    required this.speed,
  });
}

/// Animated Mesh Background Widget
/// Handles animation lifecycle efficiently
class MeshBackground extends StatefulWidget {
  final Color nodeColor;
  final Color lineColor;
  final Color glowColor;

  const MeshBackground({
    super.key,
    required this.nodeColor,
    required this.lineColor,
    required this.glowColor,
  });

  @override
  State<MeshBackground> createState() => _MeshBackgroundState();
}

class _MeshBackgroundState extends State<MeshBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20), // Slow, subtle movement
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: MeshBackgroundPainter(
              nodeColor: widget.nodeColor,
              lineColor: widget.lineColor,
              glowColor: widget.glowColor,
              animationValue: _controller.value,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}
