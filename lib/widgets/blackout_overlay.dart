import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/blackout_service.dart';

class BlackoutOverlay extends StatefulWidget {
  const BlackoutOverlay({super.key});

  @override
  State<BlackoutOverlay> createState() => _BlackoutOverlayState();
}

class _BlackoutOverlayState extends State<BlackoutOverlay> {
  bool _showHint = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: BlackoutService.instance.enabled,
      builder: (context, enabled, child) {
        if (!enabled) return const SizedBox.shrink();

        // AbsorbPointer prevents interaction with underlying app
        // WillPopScope (or PopScope) prevents back button exit
        return PopScope(
          canPop: false,
          child: Material(
            color: Colors.black,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () async {
                await HapticFeedback.heavyImpact();
                await BlackoutService.instance.disable();
              },
              onTap: () {
                if (!_showHint) {
                  setState(() => _showHint = true);
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) setState(() => _showHint = false);
                  });
                }
              },
              child: Stack(
                children: [
                  const Center(child: SizedBox()), // Fill space
                  if (_showHint)
                    const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.touch_app,
                            color: Colors.white12,
                            size: 48,
                          ),
                          SizedBox(height: 16),
                          Text(
                            "HOLD TO EXIT",
                            style: TextStyle(
                              color: Colors.white12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
