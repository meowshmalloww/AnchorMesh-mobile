import 'package:flutter/material.dart';

/// ResQ Design System - "Ceramic Stealth" Theme
///
/// A premium, tactile design language for mission-critical disaster response.
/// Light Mode: Warm ceramic surfaces with approachable feel
/// Dark Mode: Carbon black stealth with high contrast

class ResQColors extends ThemeExtension<ResQColors> {
  // Core surfaces
  final Color surface;
  final Color surfaceElevated;
  final Color surfacePressed;

  // Accent colors
  final Color accent; // Rescue red - SOS, critical
  final Color accentSecondary; // Teal safety - success, mesh active
  final Color accentMuted; // Subdued accent for backgrounds

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textOnAccent;

  // Mesh network visualization
  final Color meshNode;
  final Color meshLine;
  final Color meshGlow;

  // Status
  final Color statusOnline;
  final Color statusOffline;
  final Color statusWarning;

  // Shadows & overlays
  final Color shadowColor;
  final Color overlayColor;

  const ResQColors({
    required this.surface,
    required this.surfaceElevated,
    required this.surfacePressed,
    required this.accent,
    required this.accentSecondary,
    required this.accentMuted,
    required this.textPrimary,
    required this.textSecondary,
    required this.textOnAccent,
    required this.meshNode,
    required this.meshLine,
    required this.meshGlow,
    required this.statusOnline,
    required this.statusOffline,
    required this.statusWarning,
    required this.shadowColor,
    required this.overlayColor,
  });

  /// Light Mode: "Ceramic" - Warm, approachable, trustworthy
  static const light = ResQColors(
    surface: Color(0xFFF5F3F0), // Warm ceramic white
    surfaceElevated: Color(0xFFFFFFFF), // Pure white cards
    surfacePressed: Color(0xFFE8E5E1), // Pressed state
    accent: Color(0xFFE63946), // Rescue red
    accentSecondary: Color(0xFF2A9D8F), // Teal safety
    accentMuted: Color(0xFFFCE8EA), // Light red tint
    textPrimary: Color(0xFF1D1D1F), // Near black
    textSecondary: Color(0xFF6B6B6F), // Medium grey
    textOnAccent: Color(0xFFFFFFFF), // White on colored
    meshNode: Color(0xFFB8B4AE), // Subtle grey nodes
    meshLine: Color(0xFFD1CEC9), // Light grey lines
    meshGlow: Color(0x332A9D8F), // Teal glow 20%
    statusOnline: Color(0xFF2A9D8F), // Teal
    statusOffline: Color(0xFFE63946), // Red
    statusWarning: Color(0xFFF4A261), // Amber
    shadowColor: Color(0x1A1D1D1F), // 10% black
    overlayColor: Color(0x80F5F3F0), // 50% surface
  );

  /// Dark Mode: "Stealth" - Tactical, premium, high contrast
  static const dark = ResQColors(
    surface: Color(0xFF0D0E10), // Carbon black
    surfaceElevated: Color(0xFF1A1C1F), // Elevated dark grey
    surfacePressed: Color(0xFF252729), // Pressed state
    accent: Color(0xFFFF4757), // Bright rescue red
    accentSecondary: Color(0xFF00D9B5), // Bright teal
    accentMuted: Color(0xFF2A1F20), // Dark red tint
    textPrimary: Color(0xFFF5F5F7), // Near white
    textSecondary: Color(0xFF8E8E93), // Medium grey
    textOnAccent: Color(0xFFFFFFFF), // White on colored
    meshNode: Color(0xFF3A3D42), // Dark grey nodes
    meshLine: Color(0xFF2A2D32), // Darker grey lines
    meshGlow: Color(0x3300D9B5), // Teal glow 20%
    statusOnline: Color(0xFF00D9B5), // Bright teal
    statusOffline: Color(0xFFFF4757), // Bright red
    statusWarning: Color(0xFFFFB347), // Bright amber
    shadowColor: Color(0x40000000), // 25% black
    overlayColor: Color(0x800D0E10), // 50% surface
  );

  @override
  ResQColors copyWith({
    Color? surface,
    Color? surfaceElevated,
    Color? surfacePressed,
    Color? accent,
    Color? accentSecondary,
    Color? accentMuted,
    Color? textPrimary,
    Color? textSecondary,
    Color? textOnAccent,
    Color? meshNode,
    Color? meshLine,
    Color? meshGlow,
    Color? statusOnline,
    Color? statusOffline,
    Color? statusWarning,
    Color? shadowColor,
    Color? overlayColor,
  }) {
    return ResQColors(
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfacePressed: surfacePressed ?? this.surfacePressed,
      accent: accent ?? this.accent,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      accentMuted: accentMuted ?? this.accentMuted,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textOnAccent: textOnAccent ?? this.textOnAccent,
      meshNode: meshNode ?? this.meshNode,
      meshLine: meshLine ?? this.meshLine,
      meshGlow: meshGlow ?? this.meshGlow,
      statusOnline: statusOnline ?? this.statusOnline,
      statusOffline: statusOffline ?? this.statusOffline,
      statusWarning: statusWarning ?? this.statusWarning,
      shadowColor: shadowColor ?? this.shadowColor,
      overlayColor: overlayColor ?? this.overlayColor,
    );
  }

  @override
  ResQColors lerp(ThemeExtension<ResQColors>? other, double t) {
    if (other is! ResQColors) return this;
    return ResQColors(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfacePressed: Color.lerp(surfacePressed, other.surfacePressed, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textOnAccent: Color.lerp(textOnAccent, other.textOnAccent, t)!,
      meshNode: Color.lerp(meshNode, other.meshNode, t)!,
      meshLine: Color.lerp(meshLine, other.meshLine, t)!,
      meshGlow: Color.lerp(meshGlow, other.meshGlow, t)!,
      statusOnline: Color.lerp(statusOnline, other.statusOnline, t)!,
      statusOffline: Color.lerp(statusOffline, other.statusOffline, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
      overlayColor: Color.lerp(overlayColor, other.overlayColor, t)!,
    );
  }
}

/// Extension for easy access
extension ResQThemeExtension on BuildContext {
  ResQColors get resq =>
      Theme.of(this).extension<ResQColors>() ?? ResQColors.light;
}

/// Spring physics constants for animations
class ResQPhysics {
  ResQPhysics._();

  /// Default spring for most UI animations
  static const SpringDescription defaultSpring = SpringDescription(
    mass: 1.0,
    stiffness: 300.0,
    damping: 20.0,
  );

  /// Snappy spring for quick interactions
  static const SpringDescription snappySpring = SpringDescription(
    mass: 0.8,
    stiffness: 400.0,
    damping: 25.0,
  );

  /// Bouncy spring for playful elements
  static const SpringDescription bouncySpring = SpringDescription(
    mass: 1.0,
    stiffness: 200.0,
    damping: 12.0,
  );

  /// Slow spring for background animations
  static const SpringDescription gentleSpring = SpringDescription(
    mass: 1.5,
    stiffness: 100.0,
    damping: 15.0,
  );
}
