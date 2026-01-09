import 'package:flutter/material.dart';
import 'services/platform_service.dart';

class CustomBottomBar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const CustomBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  State<CustomBottomBar> createState() => _CustomBottomBarState();
}

class _CustomBottomBarState extends State<CustomBottomBar> {
  @override
  void initState() {
    super.initState();
    // Apply iOS 26 Liquid Glass effect to the taskbar
    PlatformService.instance.applyLiquidGlass('bottom_taskbar', intensity: 0.85);
    // Apply Android native theme integration
    PlatformService.instance.applyAndroidNativeTheme('bottom_taskbar_material_you');
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? Colors.black.withAlpha(180) : Colors.white.withAlpha(180);
    final shadowColor = isDarkMode ? Colors.white12 : Colors.black12;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10.0)),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 10,
            spreadRadius: 2,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavBarItem(
                context,
                Icons.support_rounded,
                "SOS",
                0,
                isSOS: true,
              ),
              _buildNavBarItem(context, Icons.map_rounded, "Map", 1),
              _buildNavBarItem(context, Icons.build_rounded, "Utilities", 2),
              _buildNavBarItem(context, Icons.settings_rounded, "Settings", 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavBarItem(
    BuildContext context,
    IconData icon,
    String label,
    int index, {
    bool isSOS = false,
  }) {
    final isSelected = widget.selectedIndex == index;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    // Adapt color based on theme: White for Dark Mode, Black for Light Mode
    final color = isDarkMode ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: () => widget.onItemSelected(index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 0.0),
        child: AnimatedScale(
          scale: isSelected ? 1.2 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: isSOS ? 28 : 26, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontFamily: 'Roboto',
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
