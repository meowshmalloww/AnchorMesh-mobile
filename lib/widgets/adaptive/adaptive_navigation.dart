import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/adaptive_theme.dart';

/// A glass-effect bottom navigation bar.
///
/// Replaces the standard BottomNavigationBar with a translucent glass effect
/// that adapts to platform capabilities.
class AdaptiveBottomNavBar extends StatelessWidget {
  /// Currently selected index
  final int selectedIndex;

  /// Callback when an item is selected
  final ValueChanged<int> onItemSelected;

  /// Navigation items
  final List<AdaptiveNavItem> items;

  /// Glass effect intensity
  final double intensity;

  /// Height of the navigation bar (excluding safe area)
  final double height;

  const AdaptiveBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.items,
    this.intensity = 0.85,
    this.height = 60,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adaptive = context.adaptiveTheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: adaptive?.getBlurFilter(intensity: intensity) ??
            ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: height + bottomPadding,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withAlpha((intensity * 180).round())
                : Colors.white.withAlpha((intensity * 200).round()),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white.withAlpha(30) : Colors.black.withAlpha(15),
                width: 0.5,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(15),
                blurRadius: 10,
                spreadRadius: 2,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: items.asMap().entries.map((entry) {
                  return _buildNavItem(context, entry.key, entry.value, isDark);
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int index, AdaptiveNavItem item, bool isDark) {
    final isSelected = selectedIndex == index;
    final color = isDark ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: () => onItemSelected(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: isSelected ? 1.15 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.icon,
              size: item.isLarge ? 28 : 26,
              color: color,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
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
    );
  }
}

/// A navigation item for AdaptiveBottomNavBar
class AdaptiveNavItem {
  final IconData icon;
  final String label;
  final bool isLarge;

  const AdaptiveNavItem({
    required this.icon,
    required this.label,
    this.isLarge = false,
  });
}

/// A glass-effect app bar.
class AdaptiveAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Title widget or text
  final Widget? title;

  /// Leading widget (typically back button)
  final Widget? leading;

  /// Action widgets
  final List<Widget>? actions;

  /// Whether to center the title
  final bool centerTitle;

  /// Glass effect intensity
  final double intensity;

  /// Optional bottom widget (like TabBar)
  final PreferredSizeWidget? bottom;

  /// Height of the app bar (excluding status bar)
  final double toolbarHeight;

  const AdaptiveAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.centerTitle = true,
    this.intensity = 0.8,
    this.bottom,
    this.toolbarHeight = 56,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        toolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adaptive = context.adaptiveTheme;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return ClipRRect(
      child: BackdropFilter(
        filter: adaptive?.getBlurFilter(intensity: intensity) ??
            ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: statusBarHeight + preferredSize.height,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withAlpha((intensity * 150).round())
                : Colors.white.withAlpha((intensity * 180).round()),
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(10),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                SizedBox(
                  height: toolbarHeight,
                  child: NavigationToolbar(
                    leading: leading,
                    middle: title,
                    trailing: actions != null
                        ? Row(mainAxisSize: MainAxisSize.min, children: actions!)
                        : null,
                    centerMiddle: centerTitle,
                    middleSpacing: 16,
                  ),
                ),
                if (bottom != null) bottom!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A glass-effect tab bar.
class AdaptiveTabBar extends StatelessWidget implements PreferredSizeWidget {
  /// Tab controller
  final TabController? controller;

  /// Tab labels
  final List<Widget> tabs;

  /// Glass effect intensity
  final double intensity;

  /// Whether tabs are scrollable
  final bool isScrollable;

  /// Tab indicator color
  final Color? indicatorColor;

  /// Selected label color
  final Color? labelColor;

  /// Unselected label color
  final Color? unselectedLabelColor;

  const AdaptiveTabBar({
    super.key,
    this.controller,
    required this.tabs,
    this.intensity = 0.7,
    this.isScrollable = false,
    this.indicatorColor,
    this.labelColor,
    this.unselectedLabelColor,
  });

  @override
  Size get preferredSize => const Size.fromHeight(46);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adaptive = context.adaptiveTheme;
    final theme = Theme.of(context);

    return ClipRRect(
      child: BackdropFilter(
        filter: adaptive?.getBlurFilter(intensity: intensity) ??
            ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withAlpha((intensity * 100).round())
                : Colors.white.withAlpha((intensity * 120).round()),
          ),
          child: TabBar(
            controller: controller,
            tabs: tabs,
            isScrollable: isScrollable,
            indicatorColor: indicatorColor ?? theme.colorScheme.primary,
            labelColor: labelColor ?? (isDark ? Colors.white : Colors.black),
            unselectedLabelColor: unselectedLabelColor ?? Colors.grey,
            dividerColor: Colors.transparent,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
          ),
        ),
      ),
    );
  }
}

/// A glass-effect floating action button.
class AdaptiveFAB extends StatelessWidget {
  /// Icon to display
  final IconData icon;

  /// Callback when pressed
  final VoidCallback? onPressed;

  /// Background color
  final Color? backgroundColor;

  /// Icon color
  final Color? iconColor;

  /// Glass effect intensity
  final double intensity;

  /// Size of the FAB
  final double size;

  const AdaptiveFAB({
    super.key,
    required this.icon,
    this.onPressed,
    this.backgroundColor,
    this.iconColor,
    this.intensity = 0.8,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adaptive = context.adaptiveTheme;
    final bgColor = backgroundColor ?? Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: BackdropFilter(
          filter: adaptive?.getBlurFilter(intensity: intensity) ??
              ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bgColor.withAlpha((intensity * 230).round()),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? Colors.white.withAlpha(40) : Colors.white.withAlpha(60),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: bgColor.withAlpha(80),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: iconColor ?? Colors.white,
              size: size * 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
