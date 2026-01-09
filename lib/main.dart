import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'theme_notifier.dart';
import 'services/platform_service.dart';
import 'services/connectivity_service.dart';
import 'services/version_detector.dart';
import 'theme/adaptive_theme.dart';
import 'widgets/native_theme_widget.dart';
import 'widgets/adaptive/adaptive_dialogs.dart';

/// Cached adaptive theme extension for performance
AdaptiveThemeExtension? _cachedAdaptiveTheme;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Handle Flutter errors gracefully
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  // Initialize version detector and adaptive theme early
  await VersionDetector.instance.initialize();
  _cachedAdaptiveTheme = await AdaptiveThemeExtension.detect();

  // Initialize platform service
  PlatformService.instance;

  // Start connectivity and disaster monitoring
  ConnectivityChecker.instance.startMonitoring();
  DisasterMonitor.instance.startMonitoring();

  // Start auto-activate monitoring (activates mesh on 3 failed pings)
  PlatformService.instance.startAutoActivateMonitoring();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Check low power mode on startup
    _checkLowPowerMode();

    // Listen for auto-activate events
    PlatformService.instance.autoActivateStream.listen((activated) {
      if (activated) {
        _showAutoActivateAlert();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground - check low power mode
      _checkLowPowerMode();
    }
  }

  Future<void> _checkLowPowerMode() async {
    final isLowPower = await PlatformService.instance.checkLowPowerMode();
    if (isLowPower && mounted) {
      // Show warning after app is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showLowPowerModeWarning();
      });
    }
  }

  void _showLowPowerModeWarning() {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showAdaptiveAlertDialog(
      context: context,
      title: 'Low Power Mode',
      content: 'Low Power Mode is enabled. This may prevent the mesh from working reliably.\n\n'
          'Please disable Low Power Mode in Settings > Battery for best results.',
      confirmText: 'I Understand',
    );
  }

  void _showAutoActivateAlert() {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showAdaptiveAlertDialog(
      context: context,
      title: 'No Internet',
      content: 'Internet connection lost for an extended period.\n\n'
          'Mesh mode can be activated to communicate with nearby devices.\n\n'
          'Go to the SOS tab to send a distress signal.',
      confirmText: 'OK',
      isDestructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NativeThemeProvider(
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeNotifier(),
        builder: (context, themeMode, child) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Mesh SOS',
            debugShowCheckedModeBanner: false,
            themeMode: themeMode,
            theme: _buildLightTheme(),
            darkTheme: _buildDarkTheme(),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }

  ThemeData _buildLightTheme() {
    final colorScheme = _cachedAdaptiveTheme?.accentColor != null
        ? ColorScheme.fromSeed(
            seedColor: _cachedAdaptiveTheme!.accentColor!,
            brightness: Brightness.light,
          )
        : ColorScheme.fromSeed(seedColor: Colors.deepPurple);

    return ThemeData(
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.white,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      extensions: [
        _cachedAdaptiveTheme ?? const AdaptiveThemeExtension(),
      ],
    );
  }

  ThemeData _buildDarkTheme() {
    final colorScheme = _cachedAdaptiveTheme?.accentColor != null
        ? ColorScheme.fromSeed(
            seedColor: _cachedAdaptiveTheme!.accentColor!,
            brightness: Brightness.dark,
          )
        : ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.black,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      extensions: [
        _cachedAdaptiveTheme ?? const AdaptiveThemeExtension(),
      ],
    );
  }
}

/// Global navigator key for showing dialogs from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
