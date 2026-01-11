import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:vibration/vibration.dart';
import '../theme/resq_theme.dart';

/// Premium SOS Button
///
/// A central, screen-dominating emergency trigger that looks like a
/// high-end physical object with spring-based animations and haptics.
class SOSButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isActive;
  final double size;

  const SOSButton({
    super.key,
    required this.onPressed,
    this.isActive = false,
    this.size = 180,
  });

  @override
  State<SOSButton> createState() => _SOSButtonState();
}

class _SOSButtonState extends State<SOSButton> with TickerProviderStateMixin {
  // Idle pulse animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Press spring animation
  late AnimationController _pressController;
  double _pressScale = 1.0;

  // Ring rotation
  late AnimationController _ringController;

  bool _isPressed = false;

  @override
  void initState() {
    super.initState();

    // Subtle idle pulse
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Press spring
    _pressController = AnimationController.unbounded(vsync: this);
    _pressController.addListener(() {
      if (mounted) setState(() => _pressScale = _pressController.value);
    });

    // Ring rotation (slow)
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pressController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _animatePress(0.92);
    Vibration.vibrate(duration: 10, amplitude: 64);
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _animatePress(1.0);
    widget.onPressed();
    Vibration.vibrate(duration: 50, amplitude: 128);
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _animatePress(1.0);
  }

  void _animatePress(double target) {
    final simulation = SpringSimulation(
      ResQPhysics.snappySpring,
      _pressScale,
      target,
      0,
    );

    _pressController.animateWith(simulation);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.resq;
    final size = widget.size;

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _ringController]),
      builder: (context, child) {
        final pulse = _pulseAnimation.value;
        final scale = _pressScale * pulse;

        return Transform.scale(
          scale: scale,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer glow
                if (widget.isActive)
                  Container(
                    width: size * 1.3,
                    height: size * 1.3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colors.accent.withAlpha(102),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                  ),

                // Rotating outer ring
                Transform.rotate(
                  angle: _ringController.value * 2 * pi,
                  child: CustomPaint(
                    size: Size(size * 1.15, size * 1.15),
                    painter: _RingPainter(
                      color: colors.accent.withAlpha(77),
                      strokeWidth: 2,
                      dashCount: 24,
                    ),
                  ),
                ),

                // Main button body
                GestureDetector(
                  onTapDown: _onTapDown,
                  onTapUp: _onTapUp,
                  onTapCancel: _onTapCancel,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.3, -0.3),
                        colors: [
                          colors.accent,
                          Color.lerp(colors.accent, Colors.black, 0.3)!,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadowColor,
                          blurRadius: _isPressed ? 8 : 20,
                          offset: Offset(0, _isPressed ? 4 : 10),
                        ),
                        BoxShadow(
                          color: colors.accent.withAlpha(77),
                          blurRadius: 30,
                          spreadRadius: -5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_rounded,
                            size: size * 0.35,
                            color: colors.textOnAccent,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'SOS',
                            style: TextStyle(
                              color: colors.textOnAccent,
                              fontSize: size * 0.15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Inner ring highlight
                Container(
                  width: size * 0.85,
                  height: size * 0.85,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withAlpha(51),
                      width: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Dashed ring painter for rotating effect
class _RingPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final int dashCount;

  _RingPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth;
    final dashAngle = (2 * pi) / dashCount;
    final gapAngle = dashAngle * 0.4;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * dashAngle;
      final sweepAngle = dashAngle - gapAngle;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
