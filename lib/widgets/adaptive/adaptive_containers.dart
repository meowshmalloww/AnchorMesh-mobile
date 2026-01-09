import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/adaptive_theme.dart';

/// A glass-effect section card for grouping related content.
///
/// Used for settings sections, info panels, and grouped content.
/// Automatically adapts to platform capabilities (Liquid Glass / Material You / blur fallback).
class AdaptiveSectionCard extends StatelessWidget {
  /// Section title displayed in header
  final String? title;

  /// Icon displayed next to title
  final IconData? icon;

  /// Icon color
  final Color? iconColor;

  /// Content widgets
  final List<Widget> children;

  /// Padding inside the card
  final EdgeInsets? padding;

  /// Margin around the card
  final EdgeInsets? margin;

  /// Glass effect intensity (0.0 - 1.0)
  final double intensity;

  /// Whether to show the header
  final bool showHeader;

  const AdaptiveSectionCard({
    super.key,
    this.title,
    this.icon,
    this.iconColor,
    required this.children,
    this.padding,
    this.margin,
    this.intensity = 0.8,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final adaptive = context.adaptiveTheme;

    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _buildGlassEffect(
          context: context,
          adaptive: adaptive,
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader && (title != null || icon != null))
                _buildHeader(context, isDark),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: iconColor ?? Colors.blue, size: 20),
            const SizedBox(width: 8),
          ],
          if (title != null)
            Text(
              title!.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
                letterSpacing: 1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGlassEffect({
    required BuildContext context,
    required AdaptiveThemeExtension? adaptive,
    required bool isDark,
    required Widget child,
  }) {
    if (adaptive?.supportsBlur ?? true) {
      return BackdropFilter(
        filter: adaptive?.getBlurFilter(intensity: intensity) ??
            ImageFilter.blur(sigmaX: 15 * intensity, sigmaY: 15 * intensity),
        child: Container(
          decoration: BoxDecoration(
            color: adaptive?.getGlassBackground(isDark ? Brightness.dark : Brightness.light) ??
                (isDark ? Colors.grey[900]!.withAlpha(230) : Colors.white.withAlpha(230)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: adaptive?.getGlassBorder(isDark ? Brightness.dark : Brightness.light) ??
                  (isDark ? Colors.white.withAlpha(26) : Colors.black.withAlpha(13)),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: adaptive?.glassShadowColor ?? Colors.black.withAlpha(20),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      );
    }

    // Solid fallback for devices without blur support
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A glass-effect card for displaying status information.
///
/// Used for status indicators, metrics, and quick info displays.
class AdaptiveStatusCard extends StatelessWidget {
  /// Icon displayed on the left
  final IconData icon;

  /// Title text
  final String title;

  /// Value/status text
  final String value;

  /// Accent color for icon background
  final Color color;

  /// Glass effect intensity
  final double intensity;

  /// Margin around the card
  final EdgeInsets? margin;

  /// Optional tap callback
  final VoidCallback? onTap;

  const AdaptiveStatusCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    this.intensity = 0.7,
    this.margin,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adaptive = context.adaptiveTheme;

    final card = Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: adaptive?.getBlurFilter(intensity: intensity) ??
              ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: adaptive?.getGlassBackground(isDark ? Brightness.dark : Brightness.light) ??
                  (isDark ? Colors.grey[900]!.withAlpha(204) : Colors.white.withAlpha(230)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(10),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }
    return card;
  }
}

/// A glass-effect card for informational content, warnings, or alerts.
class AdaptiveInfoCard extends StatelessWidget {
  /// Icon displayed on the left
  final IconData icon;

  /// Icon color (also used for border if isBordered)
  final Color color;

  /// Title text
  final String title;

  /// Subtitle/description text
  final String? subtitle;

  /// Whether to show a colored border
  final bool isBordered;

  /// Glass effect intensity
  final double intensity;

  /// Margin around the card
  final EdgeInsets? margin;

  const AdaptiveInfoCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.isBordered = false,
    this.intensity = 0.6,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adaptive = context.adaptiveTheme;

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: adaptive?.getBlurFilter(intensity: intensity) ??
              ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isBordered
                  ? color.withAlpha(20)
                  : (adaptive?.getGlassBackground(isDark ? Brightness.dark : Brightness.light) ??
                      (isDark ? Colors.grey[900]!.withAlpha(200) : Colors.grey[100]!.withAlpha(230))),
              borderRadius: BorderRadius.circular(12),
              border: isBordered ? Border.all(color: color) : null,
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isBordered ? color : null,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A glass-effect row for status displays within cards.
class AdaptiveStatusRow extends StatelessWidget {
  /// Icon displayed on the left
  final IconData icon;

  /// Title text
  final String title;

  /// Value text
  final String value;

  /// Accent color
  final Color color;

  const AdaptiveStatusRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850]!.withAlpha(128) : Colors.grey[50]!.withAlpha(200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A simple glass container with blur effect.
class AdaptiveContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final BorderRadius? borderRadius;
  final double intensity;
  final Color? tintColor;

  const AdaptiveContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.intensity = 0.8,
    this.tintColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adaptive = context.adaptiveTheme;
    final radius = borderRadius ?? BorderRadius.circular(12);

    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: adaptive?.getBlurFilter(intensity: intensity) ??
              ImageFilter.blur(sigmaX: 15 * intensity, sigmaY: 15 * intensity),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: tintColor?.withAlpha((intensity * 77).round()) ??
                  (adaptive?.getGlassBackground(isDark ? Brightness.dark : Brightness.light) ??
                      (isDark ? Colors.black.withAlpha(102) : Colors.white.withAlpha(128))),
              borderRadius: radius,
              border: Border.all(
                color: isDark ? Colors.white.withAlpha(26) : Colors.black.withAlpha(13),
                width: 0.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
