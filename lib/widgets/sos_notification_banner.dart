import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/sos_packet.dart';
import '../theme/resq_theme.dart';

/// Simple slide-in notification banner for SOS alerts
/// Shows at the top of the screen, auto-dismisses after 10 seconds
class SOSNotificationBanner extends StatefulWidget {
  final SOSPacket packet;
  final VoidCallback onDismiss;
  final VoidCallback onViewOnMap;

  const SOSNotificationBanner({
    super.key,
    required this.packet,
    required this.onDismiss,
    required this.onViewOnMap,
  });

  @override
  State<SOSNotificationBanner> createState() => _SOSNotificationBannerState();
}

class _SOSNotificationBannerState extends State<SOSNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();

    // Haptic feedback
    HapticFeedback.mediumImpact();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // Auto-dismiss after 10 seconds
    _autoDismissTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    _controller.reverse().then((_) {
      widget.onDismiss();
    });
  }

  void _viewOnMap() {
    _autoDismissTimer?.cancel();
    _controller.reverse().then((_) {
      widget.onViewOnMap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.resq;
    final statusColor = Color(widget.packet.status.colorValue);
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slideAnimation,
        child: GestureDetector(
          onTap: _viewOnMap,
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null && details.primaryVelocity! < 0) {
              _dismiss(); // Swipe up to dismiss
            }
          },
          child: Container(
            margin: EdgeInsets.only(
              top: topPadding + 8,
              left: 12,
              right: 12,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: statusColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withAlpha(80),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: Colors.black.withAlpha(40),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Status icon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        widget.packet.status.icon,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Text content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.packet.status.label,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Someone nearby needs help!',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${widget.packet.latitude.toStringAsFixed(4)}, ${widget.packet.longitude.toStringAsFixed(4)}',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),

                    // View on Map button
                    TextButton(
                      onPressed: _viewOnMap,
                      style: TextButton.styleFrom(
                        backgroundColor: statusColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'MAP',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),

                    // Close button
                    IconButton(
                      onPressed: _dismiss,
                      icon: Icon(
                        Icons.close,
                        color: colors.textSecondary,
                        size: 20,
                      ),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
