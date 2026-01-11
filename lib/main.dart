import 'dart:async';
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'pages/onboarding_page.dart';
import 'services/onboarding_service.dart';
import 'theme_notifier.dart';
import 'theme/resq_theme.dart';
import 'services/platform_service.dart';
import 'services/connectivity_service.dart';
import 'services/supabase_service.dart';
import 'services/ble_service.dart';
import 'services/packet_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Handle Flutter errors gracefully
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  // Initialize platform service
  PlatformService.instance;

  // Start connectivity and disaster monitoring
  ConnectivityChecker.instance.startMonitoring();
  DisasterMonitor.instance.startMonitoring();

  // Initialize Supabase for cloud sync
  try {
    await SupabaseService.instance.initialize();
  } catch (e) {
    // Supabase init failure is non-fatal - app works offline
    debugPrint('Supabase initialization failed: $e');
  }

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
  StreamSubscription<bool>? _autoActivateSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Check low power mode on startup
    _checkLowPowerMode();

    // Listen for auto-activate events
    _autoActivateSub = PlatformService.instance.autoActivateStream.listen((
      activated,
    ) {
      if (activated) {
        _showAutoActivateAlert();
      }
    });
  }

  @override
  void dispose() {
    _autoActivateSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground - reset services that may have stale state from iOS force quit
      _resetServicesOnResume();
      _checkLowPowerMode();
    } else if (state == AppLifecycleState.detached) {
      // App is being terminated - cleanup all services
      _disposeAllServices();
    }
  }

  /// Reset services on app resume (handles iOS force quit recovery)
  /// On iOS, Dart VM can persist across force quits, leaving stale database/timer state
  Future<void> _resetServicesOnResume() async {
    // Reset stale database connections
    await PacketStore.reset();
    // Reinitialize BLE event channel
    BLEService.instance.reinitializeEventChannel();
  }

  /// Dispose all global services when app terminates
  void _disposeAllServices() {
    debugPrint('Disposing all services...');
    ConnectivityChecker.instance.dispose();
    DisasterMonitor.instance.dispose();
    SupabaseService.instance.dispose();
    PlatformService.instance.dispose();
    BLEService.instance.dispose();
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.battery_alert, color: Colors.orange),
            SizedBox(width: 10),
            Text('Low Power Mode'),
          ],
        ),
        content: const Text(
          'Low Power Mode is enabled. This may prevent the mesh from working reliably.\n\n'
          'Please disable Low Power Mode in Settings > Battery for best results.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('I Understand'),
          ),
        ],
      ),
    );
  }

  void _showAutoActivateAlert() {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 10),
            Text('No Internet'),
          ],
        ),
        content: const Text(
          'Internet connection lost for an extended period.\n\n'
          'Mesh mode can be activated to communicate with nearby devices.\n\n'
          'Go to the SOS tab to send a distress signal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeNotifier(),
      builder: (context, themeMode, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'AnchorMesh',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFE63946),
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: ResQColors.light.surface,
            useMaterial3: true,
            extensions: const [ResQColors.light],
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFFF4757),
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: ResQColors.dark.surface,
            appBarTheme: AppBarTheme(
              backgroundColor: ResQColors.dark.surface,
              foregroundColor: ResQColors.dark.textPrimary,
            ),
            useMaterial3: true,
            extensions: const [ResQColors.dark],
          ),
          home: FutureBuilder<bool>(
            future: OnboardingService.instance.isOnboardingComplete(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                // Show loading state while checking onboarding status
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final isComplete = snapshot.data ?? false;
              if (isComplete) {
                return const HomeScreen();
              } else {
                return const OnboardingPage();
              }
            },
          ),
        );
      },
    );
  }
}

/// Global navigator key for showing dialogs from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
