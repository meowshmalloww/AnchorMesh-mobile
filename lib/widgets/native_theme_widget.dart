import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/liquid_glass_service.dart';

/// A widget that applies platform-native theming effects.
///
/// On iOS 26+: Applies Liquid Glass translucent material effect
/// On Android 12+: Uses Material You dynamic colors
///
/// Usage:
/// ```dart
/// NativeGlassContainer(
///   child: Text('Hello'),
///   intensity: 0.8,
/// )
/// ```
class NativeGlassContainer extends StatefulWidget {
  /// The child widget to display
  final Widget child;

  /// Intensity of the glass effect (0.0 - 1.0)
  final double intensity;

  /// Background color tint (optional)
  final Color? tintColor;

  /// Border radius for the container
  final BorderRadius? borderRadius;

  /// Padding inside the container
  final EdgeInsets? padding;

  /// Margin around the container
  final EdgeInsets? margin;

  /// Whether to show a subtle border
  final bool showBorder;

  /// Custom decoration (overrides default glass effect)
  final BoxDecoration? decoration;

  const NativeGlassContainer({
    super.key,
    required this.child,
    this.intensity = 0.8,
    this.tintColor,
    this.borderRadius,
    this.padding,
    this.margin,
    this.showBorder = true,
    this.decoration,
  });

  @override
  State<NativeGlassContainer> createState() => _NativeGlassContainerState();
}

class _NativeGlassContainerState extends State<NativeGlassContainer> {
  late NativeBlurSettings _blurSettings;

  @override
  void initState() {
    super.initState();
    _blurSettings = LiquidGlassService.instance.getBlurSettings(
      intensity: widget.intensity,
    );
  }

  @override
  void didUpdateWidget(NativeGlassContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intensity != widget.intensity) {
      _blurSettings = LiquidGlassService.instance.getBlurSettings(
        intensity: widget.intensity,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = widget.borderRadius ?? BorderRadius.circular(16);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Use custom decoration if provided
    if (widget.decoration != null) {
      return Container(
        margin: widget.margin,
        padding: widget.padding,
        decoration: widget.decoration,
        child: widget.child,
      );
    }

    // Platform-adaptive glass effect
    return Container(
      margin: widget.margin,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: _blurSettings.blurRadius,
            sigmaY: _blurSettings.blurRadius,
          ),
          child: Container(
            padding: widget.padding,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: _getBackgroundColor(isDark),
              border: widget.showBorder ? _getBorder(isDark) : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }

  Color _getBackgroundColor(bool isDark) {
    if (widget.tintColor != null) {
      return widget.tintColor!.withOpacity(_blurSettings.opacity * 0.5);
    }

    if (Platform.isIOS) {
      // iOS Liquid Glass style - more translucent
      return isDark
          ? Colors.black.withOpacity(_blurSettings.opacity * 0.3)
          : Colors.white.withOpacity(_blurSettings.opacity * 0.5);
    } else {
      // Android Material You style - slightly more opaque
      return isDark
          ? Colors.black.withOpacity(_blurSettings.opacity * 0.4)
          : Colors.white.withOpacity(_blurSettings.opacity * 0.6);
    }
  }

  Border _getBorder(bool isDark) {
    if (Platform.isIOS) {
      // iOS Liquid Glass border - subtle gradient effect
      return Border.all(
        color: isDark
            ? Colors.white.withOpacity(0.15)
            : Colors.white.withOpacity(0.3),
        width: 0.5,
      );
    } else {
      // Android Material You border
      return Border.all(
        color: isDark
            ? Colors.white.withOpacity(0.1)
            : Colors.black.withOpacity(0.08),
        width: 1,
      );
    }
  }
}

/// A navigation bar with native glass effect
class NativeGlassNavBar extends StatelessWidget {
  final Widget? leading;
  final Widget? title;
  final List<Widget>? actions;
  final double intensity;
  final Color? backgroundColor;
  final double height;

  const NativeGlassNavBar({
    super.key,
    this.leading,
    this.title,
    this.actions,
    this.intensity = 0.8,
    this.backgroundColor,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final blurSettings = LiquidGlassService.instance.getBlurSettings(
      intensity: intensity,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blurSettings.blurRadius,
          sigmaY: blurSettings.blurRadius,
        ),
        child: Container(
          height: height + MediaQuery.of(context).padding.top,
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
          decoration: BoxDecoration(
            color: backgroundColor ??
                (isDark
                    ? Colors.black.withOpacity(blurSettings.opacity * 0.4)
                    : Colors.white.withOpacity(blurSettings.opacity * 0.6)),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.05),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                const SizedBox(width: 8),
                leading!,
              ],
              if (title != null) ...[
                const SizedBox(width: 16),
                Expanded(child: title!),
              ] else
                const Spacer(),
              if (actions != null) ...actions!,
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card with native glass effect
class NativeGlassCard extends StatelessWidget {
  final Widget child;
  final double intensity;
  final Color? tintColor;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;

  const NativeGlassCard({
    super.key,
    required this.child,
    this.intensity = 0.7,
    this.tintColor,
    this.padding,
    this.margin,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: NativeGlassContainer(
        intensity: intensity,
        tintColor: tintColor,
        borderRadius: BorderRadius.circular(20),
        padding: padding ?? const EdgeInsets.all(16),
        margin: margin ?? const EdgeInsets.all(8),
        child: child,
      ),
    );
  }
}

/// A button with native glass effect
class NativeGlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final double intensity;
  final Color? tintColor;
  final EdgeInsets? padding;
  final BorderRadius? borderRadius;

  const NativeGlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.intensity = 0.6,
    this.tintColor,
    this.padding,
    this.borderRadius,
  });

  @override
  State<NativeGlassButton> createState() => _NativeGlassButtonState();
}

class _NativeGlassButtonState extends State<NativeGlassButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final borderRadius = widget.borderRadius ?? BorderRadius.circular(12);
    final blurSettings = LiquidGlassService.instance.getBlurSettings(
      intensity: _isPressed ? widget.intensity * 1.2 : widget.intensity,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed?.call();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: blurSettings.blurRadius,
              sigmaY: blurSettings.blurRadius,
            ),
            child: Container(
              padding: widget.padding ?? const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                color: widget.tintColor?.withOpacity(
                      _isPressed ? 0.4 : blurSettings.opacity * 0.5,
                    ) ??
                    (isDark
                        ? Colors.white.withOpacity(_isPressed ? 0.2 : 0.1)
                        : Colors.black.withOpacity(_isPressed ? 0.15 : 0.08)),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.2)
                      : Colors.black.withOpacity(0.1),
                  width: 0.5,
                ),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A bottom sheet with native glass effect
class NativeGlassBottomSheet extends StatelessWidget {
  final Widget child;
  final double intensity;
  final double? height;
  final bool showDragHandle;

  const NativeGlassBottomSheet({
    super.key,
    required this.child,
    this.intensity = 0.9,
    this.height,
    this.showDragHandle = true,
  });

  @override
  Widget build(BuildContext context) {
    final blurSettings = LiquidGlassService.instance.getBlurSettings(
      intensity: intensity,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blurSettings.blurRadius,
          sigmaY: blurSettings.blurRadius,
        ),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withOpacity(blurSettings.opacity * 0.5)
                : Colors.white.withOpacity(blurSettings.opacity * 0.7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withOpacity(0.2)
                    : Colors.black.withOpacity(0.1),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDragHandle) ...[
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.3)
                        : Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }

  /// Show this bottom sheet
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    double intensity = 0.9,
    bool isDismissible = true,
    bool enableDrag = true,
    bool showDragHandle = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: Colors.transparent,
      builder: (context) => NativeGlassBottomSheet(
        intensity: intensity,
        showDragHandle: showDragHandle,
        child: child,
      ),
    );
  }
}

/// Provider widget that initializes and provides native theme service
class NativeThemeProvider extends StatefulWidget {
  final Widget child;
  final bool autoInitialize;

  const NativeThemeProvider({
    super.key,
    required this.child,
    this.autoInitialize = true,
  });

  @override
  State<NativeThemeProvider> createState() => _NativeThemeProviderState();
}

class _NativeThemeProviderState extends State<NativeThemeProvider> {
  late StreamSubscription<NativeThemeEvent> _themeSubscription;
  int? _accentColor;

  @override
  void initState() {
    super.initState();
    if (widget.autoInitialize) {
      _initializeService();
    }
  }

  Future<void> _initializeService() async {
    await LiquidGlassService.instance.initialize();

    _themeSubscription = LiquidGlassService.instance.onThemeChange.listen((event) {
      if (event.accentColor != null && mounted) {
        setState(() {
          _accentColor = event.accentColor;
        });
      }
    });

    // Get initial accent color
    final accentColor = await LiquidGlassService.instance.getSystemAccentColor();
    if (accentColor != null && mounted) {
      setState(() {
        _accentColor = accentColor;
      });
    }
  }

  @override
  void dispose() {
    _themeSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _NativeThemeInherited(
      accentColor: _accentColor,
      child: widget.child,
    );
  }
}

class _NativeThemeInherited extends InheritedWidget {
  final int? accentColor;

  const _NativeThemeInherited({
    required this.accentColor,
    required super.child,
  });

  static _NativeThemeInherited? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_NativeThemeInherited>();
  }

  @override
  bool updateShouldNotify(_NativeThemeInherited oldWidget) {
    return accentColor != oldWidget.accentColor;
  }
}

/// Extension to easily access native theme data
extension NativeThemeExtension on BuildContext {
  /// Get the system accent color as a Color
  Color? get nativeAccentColor {
    final inherited = _NativeThemeInherited.of(this);
    if (inherited?.accentColor == null) return null;
    return Color(inherited!.accentColor!);
  }

  /// Check if Liquid Glass is supported
  bool get isLiquidGlassSupported =>
      LiquidGlassService.instance.isLiquidGlassSupported;

  /// Check if Material You is supported
  bool get isMaterialYouSupported =>
      LiquidGlassService.instance.isMaterialYouSupported;
}
