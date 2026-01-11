import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/sos_packet.dart';
import '../theme/resq_theme.dart';

/// Full-screen overlay alert when an SOS is received
class SOSAlertOverlay extends StatefulWidget {
  final SOSPacket packet;
  final VoidCallback onDismiss;
  final VoidCallback onViewOnMap;

  const SOSAlertOverlay({
    super.key,
    required this.packet,
    required this.onDismiss,
    required this.onViewOnMap,
  });

  @override
  State<SOSAlertOverlay> createState() => _SOSAlertOverlayState();
}

class _SOSAlertOverlayState extends State<SOSAlertOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Haptic feedback
    HapticFeedback.heavyImpact();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();

    // Auto-dismiss after 15 seconds if not interacted
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    _controller.reverse().then((_) {
      widget.onDismiss();
    });
  }

  void _viewOnMap() {
    _controller.reverse().then((_) {
      widget.onViewOnMap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.resq;
    final statusColor = Color(widget.packet.status.colorValue);
    final ageMinutes = widget.packet.ageSeconds ~/ 60;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                // Blurred background
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      color: Colors.black.withAlpha(150),
                    ),
                  ),
                ),

                // Alert card
                Center(
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colors.surfaceElevated,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: statusColor.withAlpha(150),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withAlpha(100),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Pulsing icon
                          _PulsingIcon(
                            icon: widget.packet.status.icon,
                            color: statusColor,
                          ),

                          const SizedBox(height: 20),

                          // Status label
                          Text(
                            widget.packet.status.label,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            'NEARBY EMERGENCY DETECTED',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Location info
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      color: statusColor,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${widget.packet.latitude.toStringAsFixed(5)}, ${widget.packet.longitude.toStringAsFixed(5)}',
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 14,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  ageMinutes == 0
                                      ? 'Just now'
                                      : '$ageMinutes minute${ageMinutes == 1 ? '' : 's'} ago',
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Action buttons
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _dismiss,
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    side: BorderSide(
                                      color: colors.textSecondary,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    'DISMISS',
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton(
                                  onPressed: _viewOnMap,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: statusColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.map, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'VIEW ON MAP',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Close button
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  right: 16,
                  child: IconButton(
                    onPressed: _dismiss,
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.surfaceElevated.withAlpha(200),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        color: colors.textPrimary,
                        size: 20,
                      ),
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

/// Pulsing icon animation
class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;

  const _PulsingIcon({required this.icon, required this.color});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _animation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.scale(
          scale: _animation.value,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withAlpha(150),
                  blurRadius: 20 * _animation.value,
                  spreadRadius: 5 * _animation.value,
                ),
              ],
            ),
            child: Icon(widget.icon, color: Colors.white, size: 40),
          ),
        );
      },
    );
  }
}
