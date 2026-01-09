import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/liquid_glass_service.dart';
import '../services/version_detector.dart';

/// Theme extension that carries Liquid Glass / Material You configuration.
///
/// This extension is added to ThemeData and can be accessed via:
/// ```dart
/// final adaptive = Theme.of(context).extension<AdaptiveThemeExtension>();
/// ```
class AdaptiveThemeExtension extends ThemeExtension<AdaptiveThemeExtension> {
  /// Whether iOS 26+ Liquid Glass is supported
  final bool supportsLiquidGlass;

  /// Whether Android 12+ Material You is supported
  final bool supportsMaterialYou;

  /// Whether blur effects are well-supported (iOS 13+ / Android 10+)
  final bool supportsBlur;

  /// Default glass effect intensity (0.0 - 1.0)
  final double glassIntensity;

  /// System accent color (from wallpaper on Android, tint on iOS)
  final Color? accentColor;

  /// Glass background color for light mode
  final Color glassBackgroundLight;

  /// Glass background color for dark mode
  final Color glassBackgroundDark;

  /// Glass border color for light mode
  final Color glassBorderLight;

  /// Glass border color for dark mode
  final Color glassBorderDark;

  /// Blur radius for glass effects
  final double blurRadius;

  /// Shadow color for glass containers
  final Color glassShadowColor;

  const AdaptiveThemeExtension({
    this.supportsLiquidGlass = false,
    this.supportsMaterialYou = false,
    this.supportsBlur = true,
    this.glassIntensity = 0.8,
    this.accentColor,
    this.glassBackgroundLight = const Color(0x80FFFFFF),
    this.glassBackgroundDark = const Color(0x40000000),
    this.glassBorderLight = const Color(0x30FFFFFF),
    this.glassBorderDark = const Color(0x20FFFFFF),
    this.blurRadius = 15.0,
    this.glassShadowColor = const Color(0x1A000000),
  });

  /// Create extension with detected platform capabilities
  static Future<AdaptiveThemeExtension> detect() async {
    final detector = VersionDetector.instance;
    await detector.initialize();

    final liquidGlass = await detector.supportsLiquidGlass();
    final materialYou = await detector.supportsMaterialYou();
    final blur = await detector.supportsBlurEffects();

    // Get system accent color
    Color? accent;
    try {
      final accentInt = await LiquidGlassService.instance.getSystemAccentColor();
      if (accentInt != null) {
        accent = Color(accentInt);
      }
    } catch (_) {}

    // Platform-specific blur settings
    final blurRadius = Platform.isIOS
        ? (liquidGlass ? 20.0 : 15.0)
        : (materialYou ? 12.0 : 10.0);

    // Platform-specific opacity
    final lightOpacity = Platform.isIOS ? 0.5 : 0.6;
    final darkOpacity = Platform.isIOS ? 0.3 : 0.4;

    return AdaptiveThemeExtension(
      supportsLiquidGlass: liquidGlass,
      supportsMaterialYou: materialYou,
      supportsBlur: blur,
      glassIntensity: 0.8,
      accentColor: accent,
      glassBackgroundLight: Colors.white.withAlpha((lightOpacity * 255).round()),
      glassBackgroundDark: Colors.black.withAlpha((darkOpacity * 255).round()),
      glassBorderLight: Colors.white.withAlpha(77), // 0.3 * 255
      glassBorderDark: Colors.white.withAlpha(51),  // 0.2 * 255
      blurRadius: blurRadius,
      glassShadowColor: Colors.black.withAlpha(26), // 0.1 * 255
    );
  }

  /// Get glass background color based on current brightness
  Color getGlassBackground(Brightness brightness) {
    return brightness == Brightness.dark ? glassBackgroundDark : glassBackgroundLight;
  }

  /// Get glass border color based on current brightness
  Color getGlassBorder(Brightness brightness) {
    return brightness == Brightness.dark ? glassBorderDark : glassBorderLight;
  }

  /// Get blur filter for glass effects
  ImageFilter getBlurFilter({double? intensity}) {
    final effectiveIntensity = intensity ?? glassIntensity;
    final sigma = blurRadius * effectiveIntensity;
    return ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
  }

  /// Whether any glass effects are supported
  bool get hasGlassSupport => supportsLiquidGlass || supportsMaterialYou || supportsBlur;

  @override
  AdaptiveThemeExtension copyWith({
    bool? supportsLiquidGlass,
    bool? supportsMaterialYou,
    bool? supportsBlur,
    double? glassIntensity,
    Color? accentColor,
    Color? glassBackgroundLight,
    Color? glassBackgroundDark,
    Color? glassBorderLight,
    Color? glassBorderDark,
    double? blurRadius,
    Color? glassShadowColor,
  }) {
    return AdaptiveThemeExtension(
      supportsLiquidGlass: supportsLiquidGlass ?? this.supportsLiquidGlass,
      supportsMaterialYou: supportsMaterialYou ?? this.supportsMaterialYou,
      supportsBlur: supportsBlur ?? this.supportsBlur,
      glassIntensity: glassIntensity ?? this.glassIntensity,
      accentColor: accentColor ?? this.accentColor,
      glassBackgroundLight: glassBackgroundLight ?? this.glassBackgroundLight,
      glassBackgroundDark: glassBackgroundDark ?? this.glassBackgroundDark,
      glassBorderLight: glassBorderLight ?? this.glassBorderLight,
      glassBorderDark: glassBorderDark ?? this.glassBorderDark,
      blurRadius: blurRadius ?? this.blurRadius,
      glassShadowColor: glassShadowColor ?? this.glassShadowColor,
    );
  }

  @override
  AdaptiveThemeExtension lerp(ThemeExtension<AdaptiveThemeExtension>? other, double t) {
    if (other is! AdaptiveThemeExtension) return this;

    return AdaptiveThemeExtension(
      supportsLiquidGlass: t < 0.5 ? supportsLiquidGlass : other.supportsLiquidGlass,
      supportsMaterialYou: t < 0.5 ? supportsMaterialYou : other.supportsMaterialYou,
      supportsBlur: t < 0.5 ? supportsBlur : other.supportsBlur,
      glassIntensity: lerpDouble(glassIntensity, other.glassIntensity, t) ?? glassIntensity,
      accentColor: Color.lerp(accentColor, other.accentColor, t),
      glassBackgroundLight: Color.lerp(glassBackgroundLight, other.glassBackgroundLight, t)!,
      glassBackgroundDark: Color.lerp(glassBackgroundDark, other.glassBackgroundDark, t)!,
      glassBorderLight: Color.lerp(glassBorderLight, other.glassBorderLight, t)!,
      glassBorderDark: Color.lerp(glassBorderDark, other.glassBorderDark, t)!,
      blurRadius: lerpDouble(blurRadius, other.blurRadius, t) ?? blurRadius,
      glassShadowColor: Color.lerp(glassShadowColor, other.glassShadowColor, t)!,
    );
  }
}

/// Extension on BuildContext for easy access to adaptive theme
extension AdaptiveThemeContext on BuildContext {
  /// Get the adaptive theme extension
  AdaptiveThemeExtension? get adaptiveTheme =>
      Theme.of(this).extension<AdaptiveThemeExtension>();

  /// Whether glass effects are supported
  bool get hasGlassSupport => adaptiveTheme?.hasGlassSupport ?? false;

  /// Whether Liquid Glass is supported (iOS 26+)
  bool get supportsLiquidGlass => adaptiveTheme?.supportsLiquidGlass ?? false;

  /// Whether Material You is supported (Android 12+)
  bool get supportsMaterialYou => adaptiveTheme?.supportsMaterialYou ?? false;

  /// Get glass background for current theme brightness
  Color get glassBackground {
    final brightness = Theme.of(this).brightness;
    return adaptiveTheme?.getGlassBackground(brightness) ??
        (brightness == Brightness.dark
            ? Colors.black.withAlpha(102)
            : Colors.white.withAlpha(128));
  }

  /// Get glass border for current theme brightness
  Color get glassBorder {
    final brightness = Theme.of(this).brightness;
    return adaptiveTheme?.getGlassBorder(brightness) ??
        (brightness == Brightness.dark
            ? Colors.white.withAlpha(51)
            : Colors.white.withAlpha(77));
  }

  /// Get blur filter for glass effects
  ImageFilter get glassBlur =>
      adaptiveTheme?.getBlurFilter() ??
      ImageFilter.blur(sigmaX: 15, sigmaY: 15);
}

/// Helper to create ColorScheme from Material You palette
Future<ColorScheme> createAdaptiveColorScheme({
  required Brightness brightness,
  Color fallbackSeed = Colors.deepPurple,
}) async {
  if (Platform.isAndroid) {
    final detector = VersionDetector.instance;
    await detector.initialize();

    if (await detector.supportsMaterialYou()) {
      final palette = await LiquidGlassService.instance.getMaterialYouPalette();
      if (palette != null && palette.primary != null) {
        return ColorScheme.fromSeed(
          seedColor: Color(palette.primary!),
          brightness: brightness,
        );
      }
    }
  }

  // Fallback to default seed color
  return ColorScheme.fromSeed(
    seedColor: fallbackSeed,
    brightness: brightness,
  );
}
