import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/resq_theme.dart';

/// A frosted-glass app bar with blur effect.
///
/// Use with Scaffold's `extendBodyBehindAppBar: true` for content
/// to scroll behind the translucent bar.
class FrostedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final double blurSigma;
  final bool centerTitle;
  final bool automaticallyImplyLeading;

  const FrostedAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.blurSigma = 15.0,
    this.centerTitle = true,
    this.automaticallyImplyLeading = true,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.resq;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.of(context).padding.top;

    // Check if we can pop for back button
    final canPop = Navigator.of(context).canPop();
    final showLeading = leading != null ||
        (automaticallyImplyLeading && canPop);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: EdgeInsets.only(top: topPadding),
          decoration: BoxDecoration(
            color: colors.surfaceElevated.withAlpha(isDark ? 115 : 140),
            border: Border(
              bottom: BorderSide(
                color: colors.meshLine.withAlpha(76),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: kToolbarHeight,
                child: NavigationToolbar(
                  leading: showLeading
                      ? leading ??
                          IconButton(
                            icon: Icon(
                              Icons.arrow_back,
                              color: colors.textPrimary,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          )
                      : null,
                  middle: title != null
                      ? DefaultTextStyle(
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                          child: title!,
                        )
                      : null,
                  trailing: actions != null
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: actions!
                              .map((action) => IconTheme(
                                    data: IconThemeData(
                                      color: colors.textPrimary,
                                    ),
                                    child: action,
                                  ))
                              .toList(),
                        )
                      : null,
                  centerMiddle: centerTitle,
                  middleSpacing: NavigationToolbar.kMiddleSpacing,
                ),
              ),
              if (bottom != null) bottom!,
            ],
          ),
        ),
      ),
    );
  }
}
