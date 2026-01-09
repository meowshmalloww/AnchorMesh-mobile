import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/adaptive_theme.dart';

/// A glass-effect button with multiple variants.
class AdaptiveButton extends StatefulWidget {
  /// Button label
  final String label;

  /// Optional icon
  final IconData? icon;

  /// Callback when pressed
  final VoidCallback? onPressed;

  /// Button variant
  final AdaptiveButtonVariant variant;

  /// Glass effect intensity
  final double intensity;

  /// Custom background color (overrides variant)
  final Color? backgroundColor;

  /// Custom text/icon color (overrides variant)
  final Color? foregroundColor;

  /// Padding inside the button
  final EdgeInsets? padding;

  /// Border radius
  final BorderRadius? borderRadius;

  /// Whether the button takes full width
  final bool fullWidth;

  const AdaptiveButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = AdaptiveButtonVariant.primary,
    this.intensity = 0.7,
    this.backgroundColor,
    this.foregroundColor,
    this.padding,
    this.borderRadius,
    this.fullWidth = false,
  });

  @override
  State<AdaptiveButton> createState() => _AdaptiveButtonState();
}

class _AdaptiveButtonState extends State<AdaptiveButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adaptive = context.adaptiveTheme;
    final theme = Theme.of(context);

    final bgColor = widget.backgroundColor ?? _getBackgroundColor(theme, isDark);
    final fgColor = widget.foregroundColor ?? _getForegroundColor(theme, isDark);
    final radius = widget.borderRadius ?? BorderRadius.circular(12);
    final effectiveIntensity = _isPressed ? widget.intensity * 1.2 : widget.intensity;

    Widget button = GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed?.call();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: adaptive?.getBlurFilter(intensity: effectiveIntensity) ??
                ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: widget.padding ??
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: bgColor.withAlpha(_isPressed ? 200 : 150),
                borderRadius: radius,
                border: Border.all(
                  color: isDark
                      ? Colors.white.withAlpha(40)
                      : Colors.black.withAlpha(20),
                  width: 0.5,
                ),
                boxShadow: widget.variant == AdaptiveButtonVariant.primary
                    ? [
                        BoxShadow(
                          color: bgColor.withAlpha(60),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: widget.fullWidth ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: fgColor, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: fgColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }

  Color _getBackgroundColor(ThemeData theme, bool isDark) {
    switch (widget.variant) {
      case AdaptiveButtonVariant.primary:
        return theme.colorScheme.primary;
      case AdaptiveButtonVariant.secondary:
        return isDark ? Colors.grey[800]! : Colors.grey[200]!;
      case AdaptiveButtonVariant.danger:
        return Colors.red;
      case AdaptiveButtonVariant.success:
        return Colors.green;
      case AdaptiveButtonVariant.ghost:
        return Colors.transparent;
    }
  }

  Color _getForegroundColor(ThemeData theme, bool isDark) {
    switch (widget.variant) {
      case AdaptiveButtonVariant.primary:
        return Colors.white;
      case AdaptiveButtonVariant.secondary:
        return isDark ? Colors.white : Colors.black;
      case AdaptiveButtonVariant.danger:
        return Colors.white;
      case AdaptiveButtonVariant.success:
        return Colors.white;
      case AdaptiveButtonVariant.ghost:
        return isDark ? Colors.white : Colors.black;
    }
  }
}

enum AdaptiveButtonVariant { primary, secondary, danger, success, ghost }

/// A glass-effect switch/toggle list tile.
class AdaptiveSwitchTile extends StatelessWidget {
  /// Leading icon
  final IconData? icon;

  /// Title text
  final String title;

  /// Subtitle text
  final String? subtitle;

  /// Current value
  final bool value;

  /// Callback when value changes
  final ValueChanged<bool>? onChanged;

  /// Glass effect intensity
  final double intensity;

  const AdaptiveSwitchTile({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
    this.intensity = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withAlpha(value ? 15 : 8)
            : Colors.black.withAlpha(value ? 10 : 5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        secondary: icon != null ? Icon(icon, size: 20) : null,
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle!, style: const TextStyle(fontSize: 12))
            : null,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// A glass-effect radio option button.
class AdaptiveRadioOption<T> extends StatelessWidget {
  /// Option value
  final T value;

  /// Currently selected value
  final T groupValue;

  /// Callback when selected
  final ValueChanged<T>? onChanged;

  /// Option label
  final String label;

  /// Option description
  final String? description;

  /// Accent color when selected
  final Color? activeColor;

  /// Optional badge text (e.g., "~7h")
  final String? badge;

  /// Badge color
  final Color? badgeColor;

  const AdaptiveRadioOption({
    super.key,
    required this.value,
    required this.groupValue,
    this.onChanged,
    required this.label,
    this.description,
    this.activeColor,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = value == groupValue;
    final color = activeColor ?? Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: onChanged != null ? () => onChanged!(value) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withAlpha(isDark ? 30 : 20)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? color : Colors.grey,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (badgeColor ?? color).withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            badge!,
                            style: TextStyle(
                              fontSize: 10,
                              color: badgeColor ?? color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      description!,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A glass-effect slider with label and value display.
class AdaptiveSlider extends StatelessWidget {
  /// Slider label
  final String label;

  /// Current value
  final double value;

  /// Minimum value
  final double min;

  /// Maximum value
  final double max;

  /// Number of divisions
  final int? divisions;

  /// Callback when value changes
  final ValueChanged<double>? onChanged;

  /// Value formatter for display
  final String Function(double)? valueFormatter;

  /// Accent color
  final Color? activeColor;

  /// Glass effect intensity
  final double intensity;

  const AdaptiveSlider({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 100,
    this.divisions,
    this.onChanged,
    this.valueFormatter,
    this.activeColor,
    this.intensity = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = activeColor ?? Theme.of(context).colorScheme.primary;
    final displayValue = valueFormatter?.call(value) ?? value.toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 20 : 15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                displayValue,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              inactiveTrackColor: color.withAlpha(50),
              thumbColor: color,
              overlayColor: color.withAlpha(30),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// A glass-effect text field.
class AdaptiveTextField extends StatelessWidget {
  /// Text controller
  final TextEditingController? controller;

  /// Hint text
  final String? hintText;

  /// Label text
  final String? labelText;

  /// Prefix icon
  final IconData? prefixIcon;

  /// Suffix icon
  final IconData? suffixIcon;

  /// Callback for suffix icon tap
  final VoidCallback? onSuffixTap;

  /// Callback when text changes
  final ValueChanged<String>? onChanged;

  /// Callback when submitted
  final ValueChanged<String>? onSubmitted;

  /// Whether the field is obscured (password)
  final bool obscureText;

  /// Glass effect intensity
  final double intensity;

  /// Maximum lines
  final int maxLines;

  const AdaptiveTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixTap,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.intensity = 0.6,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adaptive = context.adaptiveTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: adaptive?.getBlurFilter(intensity: intensity) ??
            ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          obscureText: obscureText,
          maxLines: maxLines,
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
          decoration: InputDecoration(
            hintText: hintText,
            labelText: labelText,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
            suffixIcon: suffixIcon != null
                ? IconButton(icon: Icon(suffixIcon), onPressed: onSuffixTap)
                : null,
            filled: true,
            fillColor: isDark
                ? Colors.white.withAlpha((intensity * 30).round())
                : Colors.black.withAlpha((intensity * 15).round()),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.white.withAlpha(30) : Colors.black.withAlpha(15),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
