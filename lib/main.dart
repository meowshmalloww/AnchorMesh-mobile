import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'theme_notifier.dart';
import 'services/platform_service.dart';
import 'services/connectivity_service.dart';

void main() {
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
          title: 'Mesh SOS',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            scaffoldBackgroundColor: Colors.white,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: Colors.black,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
            useMaterial3: true,
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}

/// Global navigator key for showing dialogs from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
