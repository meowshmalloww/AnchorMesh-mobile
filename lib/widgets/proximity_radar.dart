import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../services/ble_service.dart';
import '../utils/rssi_calculator.dart';

/// Proximity Radar Widget
/// Shows a circular radar with direction and distance to SOS signals
/// User spins in a circle while the app records RSSI at each heading
class ProximityRadar extends StatefulWidget {
  final String targetDeviceId;
  final VoidCallback? onComplete;

  const ProximityRadar({
    super.key,
    required this.targetDeviceId,
    this.onComplete,
  });

  @override
  State<ProximityRadar> createState() => _ProximityRadarState();
}

class _ProximityRadarState extends State<ProximityRadar>
    with TickerProviderStateMixin {
  final DirectionFinder _directionFinder = DirectionFinder();

  double _currentHeading = 0;
  int? _strongestHeading;
  double? _distance;
  bool _isScanning = false;
  int _samplesCollected = 0;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
  }

  void _setupAnimation() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  void _startScanning() {
    setState(() {
      _isScanning = true;
      _samplesCollected = 0;
      _directionFinder.clear();
    });

    // Listen to compass heading
    FlutterCompass.events?.listen((event) {
      if (!_isScanning || event.heading == null) return;

      setState(() => _currentHeading = event.heading!);

      // Simulate receiving RSSI (in real app, this comes from BLE)
      // For now, use stored values from BLE service
      final smoothedRssi = BLEService.instance.rssiCalculator.getSmoothedRSSI(
        widget.targetDeviceId,
      );

      if (smoothedRssi != null) {
        _directionFinder.addReading(_currentHeading, smoothedRssi.round());
        setState(() {
          _samplesCollected++;
          _strongestHeading = _directionFinder.getStrongestHeading();
          _distance = RSSICalculator.calculateDistance(smoothedRssi.round());
        });

        if (_directionFinder.hasEnoughData()) {
          _stopScanning();
        }
      }
    });
  }

  void _stopScanning() {
    setState(() => _isScanning = false);
    widget.onComplete?.call();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isScanning
                ? 'Spin slowly in a circle...'
                : 'Tap to find direction',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 20),

          // Radar display
          GestureDetector(
            onTap: _isScanning ? _stopScanning : _startScanning,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return CustomPaint(
                  size: const Size(250, 250),
                  painter: RadarPainter(
                    currentHeading: _currentHeading,
                    strongestHeading: _strongestHeading,
                    isScanning: _isScanning,
                    pulseValue: _pulseAnimation.value,
                    isDark: isDark,
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // Distance indicator
          if (_distance != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.withAlpha(30),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '~${_distance!.toStringAsFixed(1)} meters',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),

          if (_strongestHeading != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Direction: ${_getDirectionName(_strongestHeading!)}',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),

          // Progress indicator
          if (_isScanning)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Samples: $_samplesCollected',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  String _getDirectionName(int heading) {
    if (heading >= 337.5 || heading < 22.5) return 'North';
    if (heading >= 22.5 && heading < 67.5) return 'Northeast';
    if (heading >= 67.5 && heading < 112.5) return 'East';
    if (heading >= 112.5 && heading < 157.5) return 'Southeast';
    if (heading >= 157.5 && heading < 202.5) return 'South';
    if (heading >= 202.5 && heading < 247.5) return 'Southwest';
    if (heading >= 247.5 && heading < 292.5) return 'West';
    return 'Northwest';
  }
}

/// Custom painter for the radar display
class RadarPainter extends CustomPainter {
  final double currentHeading;
  final int? strongestHeading;
  final bool isScanning;
  final double pulseValue;
  final bool isDark;

  RadarPainter({
    required this.currentHeading,
    this.strongestHeading,
    required this.isScanning,
    required this.pulseValue,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Background circles
    final bgPaint = Paint()
      ..color = isDark ? Colors.grey[800]! : Colors.grey[200]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, bgPaint);
    }

    // Cardinal directions
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final directions = ['N', 'E', 'S', 'W'];
    final angles = [0.0, 90.0, 180.0, 270.0];

    for (var i = 0; i < 4; i++) {
      final angle = (angles[i] - 90) * pi / 180;
      final x = center.dx + (radius + 15) * cos(angle);
      final y = center.dy + (radius + 15) * sin(angle);

      textPainter.text = TextSpan(
        text: directions[i],
        style: TextStyle(
          color: isDark ? Colors.white54 : Colors.black54,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }

    // Scanning sweep
    if (isScanning) {
      final sweepPaint = Paint()
        ..shader = SweepGradient(
          startAngle: (currentHeading - 90) * pi / 180,
          endAngle: (currentHeading - 90 + 45) * pi / 180,
          colors: [Colors.green.withAlpha(100), Colors.transparent],
        ).createShader(Rect.fromCircle(center: center, radius: radius));

      canvas.drawCircle(center, radius * pulseValue, sweepPaint);
    }

    // Current heading indicator
    final headingAngle = (currentHeading - 90) * pi / 180;
    final headingPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      center,
      Offset(
        center.dx + radius * 0.8 * cos(headingAngle),
        center.dy + radius * 0.8 * sin(headingAngle),
      ),
      headingPaint,
    );

    // Strongest signal direction
    if (strongestHeading != null) {
      final signalAngle = (strongestHeading! - 90) * pi / 180;
      final signalPaint = Paint()
        ..color = Colors.red
        ..strokeWidth = 4
        ..style = PaintingStyle.fill;

      final signalX = center.dx + radius * 0.7 * cos(signalAngle);
      final signalY = center.dy + radius * 0.7 * sin(signalAngle);

      canvas.drawCircle(Offset(signalX, signalY), 10, signalPaint);

      // Pulse effect
      final pulsePaint = Paint()
        ..color = Colors.red.withAlpha((100 * pulseValue).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(
        Offset(signalX, signalY),
        10 + 10 * pulseValue,
        pulsePaint,
      );
    }

    // Center dot
    canvas.drawCircle(center, 8, Paint()..color = Colors.blue);
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return oldDelegate.currentHeading != currentHeading ||
        oldDelegate.strongestHeading != strongestHeading ||
        oldDelegate.isScanning != isScanning ||
        oldDelegate.pulseValue != pulseValue;
  }
}
