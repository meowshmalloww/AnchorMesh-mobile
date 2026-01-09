/// Adaptive widget library for iOS Liquid Glass and Android Material You theming.
///
/// This library provides glass-effect widgets that automatically adapt to
/// platform capabilities:
/// - iOS 26+: Native Liquid Glass effects
/// - iOS 15-25: BackdropFilter blur effects
/// - Android 12+: Material You colors + blur
/// - Android 10-11: BackdropFilter blur
/// - Older platforms: Solid fallback
///
/// Usage:
/// ```dart
/// import 'package:mesh_sos/widgets/adaptive/adaptive_widgets.dart';
///
/// // Containers
/// AdaptiveSectionCard(
///   title: 'Settings',
///   icon: Icons.settings,
///   children: [...],
/// )
///
/// // Navigation
/// AdaptiveBottomNavBar(
///   selectedIndex: 0,
///   onItemSelected: (index) {},
///   items: [
///     AdaptiveNavItem(icon: Icons.home, label: 'Home'),
///   ],
/// )
///
/// // Inputs
/// AdaptiveButton(
///   label: 'Submit',
///   onPressed: () {},
/// )
///
/// // Dialogs
/// showGlassDialog(
///   context: context,
///   builder: (context) => YourDialogContent(),
/// )
/// ```
library adaptive_widgets;

// Theme extension
export '../../theme/adaptive_theme.dart';

// Container widgets
export 'adaptive_containers.dart';

// Navigation widgets
export 'adaptive_navigation.dart';

// Input widgets
export 'adaptive_inputs.dart';

// Dialog and snackbar helpers
export 'adaptive_dialogs.dart';
