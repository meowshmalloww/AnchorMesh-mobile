import 'package:flutter/material.dart';
import 'widgets/adaptive/adaptive_navigation.dart';

class CustomBottomBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;

  const CustomBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveBottomNavBar(
      selectedIndex: selectedIndex,
      onItemSelected: (index) => onItemSelected(index),
      intensity: 0.85,
      items: const [
        AdaptiveNavItem(
          icon: Icons.support_rounded,
          label: 'SOS',
          isLarge: true,
        ),
        AdaptiveNavItem(
          icon: Icons.map_rounded,
          label: 'Map',
        ),
        AdaptiveNavItem(
          icon: Icons.build_rounded,
          label: 'Utilities',
        ),
        AdaptiveNavItem(
          icon: Icons.settings_rounded,
          label: 'Settings',
        ),
      ],
    );
  }
}
