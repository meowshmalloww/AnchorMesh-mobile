import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/resq_theme.dart';

/// ResQ Navigation Bar
///
/// A floating, frosted-glass bottom navigation bar with custom
/// pill-chamfer shape and spring-based selection animations.
class ResQNavBar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const ResQNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  State<ResQNavBar> createState() => _ResQNavBarState();
}

class _ResQNavBarState extends State<ResQNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.resq;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: ClipPath(
        clipper: _NavBarClipper(),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color: colors.surfaceElevated.withAlpha(isDark ? 115 : 140),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colors.meshLine.withAlpha(128),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.shadowColor,
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildItem(0, Icons.home_rounded, 'Home', colors),
                _buildItem(1, Icons.map_rounded, 'Map', colors),
                _buildItem(2, Icons.build_rounded, 'Tools', colors),
                _buildSOSItem(3, colors),
                _buildItem(4, Icons.settings_rounded, 'Settings', colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(int index, IconData icon, String label, ResQColors colors) {
    final isSelected = widget.selectedIndex == index;

    return GestureDetector(
      onTap: () => widget.onItemSelected(index),
      behavior: HitTestBehavior.opaque,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: isSelected ? 1 : 0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 1.0 + (value * 0.15),
                  child: Icon(
                    icon,
                    size: 24,
                    color: Color.lerp(
                      colors.textSecondary,
                      colors.accentSecondary,
                      value,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: Color.lerp(
                      colors.textSecondary,
                      colors.textPrimary,
                      value,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSOSItem(int index, ResQColors colors) {
    final isSelected = widget.selectedIndex == index;

    return GestureDetector(
      onTap: () => widget.onItemSelected(index),
      behavior: HitTestBehavior.opaque,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: isSelected ? 1 : 0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 1.0 + (value * 0.15),
                  child: Icon(
                    Icons.emergency,
                    size: 24,
                    color: Color.lerp(
                      colors.textSecondary,
                      colors.accent,
                      value,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'SOS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: Color.lerp(
                      colors.textSecondary,
                      isSelected ? colors.accent : colors.textPrimary,
                      value,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Custom clipper for nav bar shape
class _NavBarClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    const radius = 20.0;
    const chamfer = 12.0;

    // Top-left chamfer
    path.moveTo(chamfer, 0);

    // Top edge
    path.lineTo(size.width - chamfer, 0);

    // Top-right chamfer
    path.lineTo(size.width, chamfer);

    // Right edge
    path.lineTo(size.width, size.height - radius);

    // Bottom-right corner
    path.quadraticBezierTo(
      size.width,
      size.height,
      size.width - radius,
      size.height,
    );

    // Bottom edge
    path.lineTo(radius, size.height);

    // Bottom-left corner
    path.quadraticBezierTo(0, size.height, 0, size.height - radius);

    // Left edge
    path.lineTo(0, chamfer);

    // Top-left chamfer close
    path.lineTo(chamfer, 0);

    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
