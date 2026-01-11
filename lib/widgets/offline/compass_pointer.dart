import 'dart:math' as math;
import 'package:flutter/material.dart';

class CompassPointer extends StatelessWidget {
  final double heading;
  final double bearing;
  final double? distance;
  final String? targetName;
  final bool isAccuracyLow;

  const CompassPointer({
    super.key,
    required this.heading,
    required this.bearing,
    this.distance,
    this.targetName,
    this.isAccuracyLow = false,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate relative angle (0 is up)
    // If bearing is 90 (East) and heading is 0 (North), arrow should point Right (90).
    // If heading is 90 (East), arrow should point Up (0).
    // relative = bearing - heading.
    double relativeAngle = (bearing - heading) * (math.pi / 180);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (targetName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              "Heading to: $targetName",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),

        Stack(
          alignment: Alignment.center,
          children: [
            // Compass Ring (North indicator)
            Transform.rotate(
              angle: -heading * (math.pi / 180),
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.grey.withAlpha(50),
                    width: 2,
                  ),
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      "N",
                      style: TextStyle(
                        color: Colors.red.withAlpha(100),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // The Giant Arrow
            Transform.rotate(
              angle: relativeAngle,
              child: const Icon(
                Icons.navigation, // Or a custom painter for "Giant Arrow"
                size: 200,
                color: Colors.blue,
              ),
            ),
          ],
        ),

        const SizedBox(height: 30),

        if (distance != null)
          Column(
            children: [
              Text(
                distance! < 1000
                    ? "${distance!.toStringAsFixed(0)}m"
                    : "${(distance! / 1000).toStringAsFixed(2)}km",
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                "DISTANCE",
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 2,
                  color: Colors.grey,
                ),
              ),
            ],
          )
        else
          const Text(
            "Waiting for GPS...",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),

        if (isAccuracyLow)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Text(
              "⚠️ Low GPS Accuracy",
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}
