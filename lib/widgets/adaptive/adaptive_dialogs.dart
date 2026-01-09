import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/adaptive_theme.dart';

/// Shows a glass-effect dialog.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  double intensity = 0.85,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor ?? Colors.black54,
    builder: (context) => AdaptiveDialogWrapper(
      intensity: intensity,
      child: builder(context),
    ),
  );
}

/// Shows a glass-effect alert dialog with standard actions.
Future<bool?> showAdaptiveAlertDialog({
  required BuildContext context,
  required String title,
  required String content,
  String confirmText = 'OK',
  String? cancelText,
  Color? confirmColor,
  bool isDestructive = false,
  double intensity = 0.85,
}) {
  return showGlassDialog<bool>(
    context: context,
    intensity: intensity,
    builder: (context) => AdaptiveAlertDialog(
      title: title,
      content: content,
      confirmText: confirmText,
      cancelText: cancelText,
      confirmColor: confirmColor,
      isDestructive: isDestructive,
    ),
  );
}

/// A glass-effect dialog wrapper.
class AdaptiveDialogWrapper extends StatelessWidget {
  final Widget child;
  final double intensity;

  const AdaptiveDialogWrapper({
    super.key,
    required this.child,
    this.intensity = 0.85,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adaptive = context.adaptiveTheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: adaptive?.getBlurFilter(intensity: intensity) ??
              ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withAlpha((intensity * 200).round())
                  : Colors.white.withAlpha((intensity * 230).round()),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? Colors.white.withAlpha(30) : Colors.black.withAlpha(15),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(40),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A glass-effect alert dialog with title, content, and actions.
class AdaptiveAlertDialog extends StatelessWidget {
  final String title;
  final String content;
  final String confirmText;
  final String? cancelText;
  final Color? confirmColor;
  final bool isDestructive;

  const AdaptiveAlertDialog({
    super.key,
    required this.title,
    required this.content,
    this.confirmText = 'OK',
    this.cancelText,
    this.confirmColor,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionColor = confirmColor ??
        (isDestructive ? Colors.red : theme.colorScheme.primary);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (cancelText != null) ...[
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(cancelText!),
                ),
                const SizedBox(width: 8),
              ],
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: actionColor),
                child: Text(confirmText),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shows a glass-effect bottom sheet.
Future<T?> showAdaptiveBottomSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool showDragHandle = true,
  double intensity = 0.9,
  double? height,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    builder: (context) => AdaptiveBottomSheetWrapper(
      intensity: intensity,
      showDragHandle: showDragHandle,
      height: height,
      child: builder(context),
    ),
  );
}

/// A glass-effect bottom sheet wrapper.
class AdaptiveBottomSheetWrapper extends StatelessWidget {
  final Widget child;
  final double intensity;
  final bool showDragHandle;
  final double? height;

  const AdaptiveBottomSheetWrapper({
    super.key,
    required this.child,
    this.intensity = 0.9,
    this.showDragHandle = true,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adaptive = context.adaptiveTheme;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: adaptive?.getBlurFilter(intensity: intensity) ??
            ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withAlpha((intensity * 200).round())
                : Colors.white.withAlpha((intensity * 230).round()),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white.withAlpha(30) : Colors.black.withAlpha(15),
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
                        ? Colors.white.withAlpha(77)
                        : Colors.black.withAlpha(51),
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
}

/// Shows a glass-effect snackbar.
void showAdaptiveSnackBar({
  required BuildContext context,
  required String message,
  IconData? icon,
  Color? backgroundColor,
  Color? textColor,
  Duration duration = const Duration(seconds: 3),
  SnackBarAction? action,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: textColor ?? Colors.white, size: 20),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: textColor ?? Colors.white),
            ),
          ),
        ],
      ),
      backgroundColor: backgroundColor ??
          (isDark ? Colors.grey[850] : Colors.grey[800]),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      duration: duration,
      action: action,
    ),
  );
}

/// Shows a success snackbar.
void showSuccessSnackBar(BuildContext context, String message) {
  showAdaptiveSnackBar(
    context: context,
    message: message,
    icon: Icons.check_circle,
    backgroundColor: Colors.green[700],
  );
}

/// Shows an error snackbar.
void showErrorSnackBar(BuildContext context, String message) {
  showAdaptiveSnackBar(
    context: context,
    message: message,
    icon: Icons.error,
    backgroundColor: Colors.red[700],
  );
}

/// Shows a warning snackbar.
void showWarningSnackBar(BuildContext context, String message) {
  showAdaptiveSnackBar(
    context: context,
    message: message,
    icon: Icons.warning,
    backgroundColor: Colors.orange[700],
  );
}

/// Shows an info snackbar.
void showInfoSnackBar(BuildContext context, String message) {
  showAdaptiveSnackBar(
    context: context,
    message: message,
    icon: Icons.info,
    backgroundColor: Colors.blue[700],
  );
}
